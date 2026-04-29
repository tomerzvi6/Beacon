"""
Security & privacy checks run by the Guardian agent.
All reads are read-only against audit_log and agent-side tables.
PHI-table probes intentionally try forbidden operations to verify grants haven't widened.
"""
import logging
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.exc import ProgrammingError

log = logging.getLogger("beacon.guardian")

_JERUSALEM = ZoneInfo("Asia/Jerusalem")
_BUSINESS_HOURS = range(6, 22)  # 06:00–21:59 local time

# Thresholds
_MAX_READS_PER_ACTOR_PER_HOUR = 100
_MAX_CROSS_HOUSEHOLD_ACTIONS = 5


# ---------------------------------------------------------------------------
# Audit log queries
# ---------------------------------------------------------------------------


def get_recent_audit_entries(engine, hours: int = 24) -> list[dict]:
    """Return audit_log rows from the last `hours` hours."""
    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT id, actor_type, actor_id, action, target_table, "
                "target_id::text, household_id::text, metadata_, created_at "
                "FROM audit_log "
                "WHERE created_at >= now() - make_interval(hours => :h) "
                "ORDER BY created_at DESC"
            ),
            {"h": hours},
        ).fetchall()
    return [dict(r._mapping) for r in rows]


def detect_offhours_access(entries: list[dict]) -> list[dict]:
    """Flag audit entries that occurred outside 06:00–22:00 Jerusalem time."""
    flagged = []
    for e in entries:
        ts: datetime = e["created_at"]
        local_hour = ts.astimezone(_JERUSALEM).hour
        if local_hour not in _BUSINESS_HOURS:
            flagged.append({
                "finding": "off_hours_access",
                "severity": "medium",
                "actor_id": e["actor_id"],
                "action": e["action"],
                "local_time": ts.astimezone(_JERUSALEM).isoformat(),
                "audit_id": e["id"],
            })
    return flagged


def detect_unusual_volume(entries: list[dict]) -> list[dict]:
    """Flag any actor with > threshold reads in any rolling-hour window."""
    from collections import defaultdict

    actor_hours: dict[tuple, int] = defaultdict(int)
    for e in entries:
        ts: datetime = e["created_at"]
        hour_key = (e["actor_id"], ts.replace(minute=0, second=0, microsecond=0))
        actor_hours[hour_key] += 1

    flagged = []
    for (actor_id, hour), count in actor_hours.items():
        if count > _MAX_READS_PER_ACTOR_PER_HOUR:
            flagged.append({
                "finding": "high_volume_access",
                "severity": "high",
                "actor_id": actor_id,
                "count": count,
                "hour": hour.isoformat(),
            })
    return flagged


def detect_cross_household_anomalies(entries: list[dict]) -> list[dict]:
    """
    Flag actions where the actor's inferred household differs from target household.
    This is a heuristic — the actor_id is a user UUID for API calls.
    """
    from collections import defaultdict

    actor_households: dict[str, set] = defaultdict(set)
    for e in entries:
        if e.get("household_id"):
            actor_households[e["actor_id"]].add(e["household_id"])

    flagged = []
    for actor_id, households in actor_households.items():
        if len(households) > _MAX_CROSS_HOUSEHOLD_ACTIONS:
            flagged.append({
                "finding": "cross_household_access",
                "severity": "high",
                "actor_id": actor_id,
                "distinct_households": len(households),
            })
    return flagged


def detect_phi_in_agent_views(engine) -> list[dict]:
    """
    Scan doc_chunks for content that looks like raw PHI (patient names / IDs).
    Simple heuristic: lines that contain Hebrew 8-digit numbers or medical ID patterns.
    """
    import re
    phi_pattern = re.compile(r"\b\d{8,9}\b")  # Israeli ID / medical record number

    flagged = []
    with engine.connect() as conn:
        rows = conn.execute(
            text("SELECT id::text, source, content FROM doc_chunks LIMIT 500")
        ).fetchall()

    for row in rows:
        if phi_pattern.search(row.content):
            flagged.append({
                "finding": "phi_leak_in_doc_chunks",
                "severity": "critical",
                "chunk_id": row.id,
                "source": row.source,
                "snippet": row.content[:80],
            })
    return flagged


# ---------------------------------------------------------------------------
# RLS probe utilities
# ---------------------------------------------------------------------------


def probe_phi_table_access(engine) -> dict[str, bool]:
    """
    Verify agent_role CANNOT read PHI columns.
    Returns {check_name: passed} — True means the table is protected.

    Connects as the same engine (agent_role). If the query raises ProgrammingError
    with "permission denied", PHI is protected. If it succeeds, PHI is exposed.
    """
    probes = {
        "tasks.title_he_blocked": "SELECT title_he FROM tasks LIMIT 1",
        "documents.raw_ocr_text_blocked": "SELECT raw_ocr_text FROM documents LIMIT 1",
        "users.apple_user_id_blocked": "SELECT apple_user_id FROM users LIMIT 1",
        "households.patient_name_blocked": "SELECT patient_name_encrypted FROM households LIMIT 1",
    }

    results: dict[str, bool] = {}
    for check_name, sql in probes.items():
        try:
            with engine.connect() as conn:
                conn.execute(text(sql)).fetchone()
            # Query succeeded — PHI column is readable; that's a FAIL
            results[check_name] = False
            log.warning("Guardian RLS probe FAILED: %s — PHI column is readable!", check_name)
        except ProgrammingError as exc:
            if "permission denied" in str(exc).lower():
                results[check_name] = True  # Expected: access blocked
            else:
                # Unexpected error (table doesn't exist, etc.) — treat as inconclusive
                results[check_name] = False
                log.error("Guardian RLS probe ERROR for %s: %s", check_name, exc)
        except Exception as exc:
            results[check_name] = False
            log.error("Guardian RLS probe unexpected error for %s: %s", check_name, exc)

    return results


# ---------------------------------------------------------------------------
# Phase 8 checks: roles, flagged documents, co-owner promotion anomaly
# ---------------------------------------------------------------------------


# Actions that caregivers should never perform
_CAREGIVER_FORBIDDEN_ACTIONS = {
    "invite_co_owner",
    "co_owner_joined",
    "gdpr_erasure",
    "restore_document",
}


def detect_unauthorized_role_actions(entries: list[dict]) -> list[dict]:
    """
    Flag audit entries where a caregiver (actor_type == "caregiver") attempted
    a co-owner/patient-only action.  These are indicative of either a privilege
    escalation bug or a misconfigured role.
    """
    flagged = []
    for e in entries:
        if e.get("actor_type") == "caregiver" and e.get("action") in _CAREGIVER_FORBIDDEN_ACTIONS:
            flagged.append({
                "finding": "unauthorized_role_action",
                "severity": "high",
                "actor_id": e["actor_id"],
                "action": e["action"],
                "audit_id": e["id"],
                "created_at": e["created_at"].isoformat() if hasattr(e["created_at"], "isoformat") else str(e["created_at"]),
            })
    return flagged


def detect_flagged_documents(engine) -> list[dict]:
    """
    Return documents with flagged_for_review=True that have not been deleted.
    Only accesses non-PHI metadata columns (id, household_id, flag_reason, created_at).
    """
    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT id::text, household_id::text, flag_reason, created_at "
                "FROM documents "
                "WHERE flagged_for_review = TRUE AND deleted_at IS NULL "
                "ORDER BY created_at DESC "
                "LIMIT 50"
            )
        ).fetchall()

    findings = []
    for row in rows:
        findings.append({
            "finding": "document_flagged_for_review",
            "severity": "medium",
            "document_id": row.id,
            "household_id": row.household_id,
            "flag_reason": row.flag_reason,
            "created_at": row.created_at.isoformat() if hasattr(row.created_at, "isoformat") else str(row.created_at),
        })
    return findings


def detect_coowner_promotion_anomaly(entries: list[dict]) -> list[dict]:
    """
    Flag if more than one co_owner_joined event occurs within 24 hours for the
    same household — indicates either a bug in the one-co-owner constraint or a
    social-engineering attempt.
    """
    from collections import defaultdict

    promotions: dict[str, list] = defaultdict(list)
    for e in entries:
        if e.get("action") == "co_owner_joined" and e.get("household_id"):
            promotions[e["household_id"]].append(e)

    flagged = []
    for household_id, events in promotions.items():
        if len(events) > 1:
            flagged.append({
                "finding": "coowner_promotion_anomaly",
                "severity": "critical",
                "household_id": household_id,
                "promotion_count": len(events),
                "actor_ids": [e["actor_id"] for e in events],
            })
    return flagged


def probe_view_exposes_only_aggregates(engine) -> list[dict]:
    """Verify the agent-side views don't accidentally surface PHI text columns."""
    expected_columns = {
        "v_unclaimed_tasks_age": {"task_id", "household_id", "category", "age_hours", "due_at"},
        "v_usage_metrics_weekly": {"week", "household_id", "category", "total_tasks",
                                   "done_tasks", "dismissed_tasks"},
        "v_dose_adherence_weekly": {"week", "household_id", "scheduled_doses", "taken_doses"},
        "v_user_engagement": {"household_id", "last_task_activity", "total_tasks",
                               "days_since_activity"},
    }

    flagged = []
    for view_name, allowed in expected_columns.items():
        try:
            with engine.connect() as conn:
                result = conn.execute(text(f"SELECT * FROM {view_name} LIMIT 0"))
                actual = set(result.keys())
            unexpected = actual - allowed
            if unexpected:
                flagged.append({
                    "finding": "view_exposes_unexpected_columns",
                    "severity": "high",
                    "view": view_name,
                    "unexpected_columns": list(unexpected),
                })
        except Exception as exc:
            flagged.append({
                "finding": "view_probe_error",
                "severity": "medium",
                "view": view_name,
                "error": str(exc),
            })

    return flagged
