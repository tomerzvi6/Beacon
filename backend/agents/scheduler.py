"""
APScheduler entry point — wires all agents to their cron triggers.

Cadences (configurable via env vars):
  GUARDIAN_HOUR        default: 7  (daily 07:00)
  CS_PROACTIVE_HOUR    default: 9  (daily 09:00)
  CS_REACTIVE_INTERVAL default: every 30 min (08:00–20:00)
  PRODUCT_CRON         default: Sunday 08:00
  CREATIVE_CRON        default: Sunday 10:00
  CHIEF_AGENT_HOUR     default: 11 (daily 11:00, after all 4 operational agents)

Run with: python agents/scheduler.py
"""
import logging
import os

from apscheduler.schedulers.blocking import BlockingScheduler

from agents.graphs import (
    generate_daily_brief,
    run_creative_weekly,
    run_customer_success_proactive,
    run_customer_success_reactive,
    run_guardian,
    run_product,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("beacon.scheduler")

_TZ = "Asia/Jerusalem"


# ---------------------------------------------------------------------------
# Job wrappers
# ---------------------------------------------------------------------------


def job_guardian() -> None:
    log.info("[Guardian] Starting daily security scan...")
    try:
        result = run_guardian()
        log.info("[Guardian] Done. run_id=%s findings=%s",
                 result.get("run_id") or "no draft",
                 len(result.get("findings", [])))
    except Exception:
        log.exception("[Guardian] Failed")


def job_cs_proactive() -> None:
    log.info("[CustomerSuccess/proactive] Starting daily batch...")
    try:
        result = run_customer_success_proactive()
        log.info("[CustomerSuccess/proactive] Done. run_id=%s",
                 result.get("run_id") or "no draft")
    except Exception:
        log.exception("[CustomerSuccess/proactive] Failed")


def job_cs_reactive() -> None:
    log.info("[CustomerSuccess/reactive] Checking for new tickets...")
    try:
        result = run_customer_success_reactive()
        log.info("[CustomerSuccess/reactive] Done. run_id=%s",
                 result.get("run_id") or "no tickets")
    except Exception:
        log.exception("[CustomerSuccess/reactive] Failed")


def job_product() -> None:
    log.info("[Product] Starting weekly report...")
    try:
        result = run_product()
        log.info("[Product] Done. run_id=%s", result.get("run_id", ""))
    except Exception:
        log.exception("[Product] Failed")


def job_creative() -> None:
    log.info("[Creative] Generating weekly content calendar...")
    try:
        result = run_creative_weekly()
        log.info("[Creative] Done. run_id=%s", result.get("run_id", ""))
    except Exception:
        log.exception("[Creative] Failed")


def job_chief_brief() -> None:
    log.info("[Chief] Generating daily brief...")
    try:
        result = generate_daily_brief()
        log.info(
            "[Chief] Done. brief_date=%s citations=%s grounding_ok=%s",
            result.get("brief_date"),
            result.get("citations_count"),
            result.get("grounding_ok"),
        )
    except Exception:
        log.exception("[Chief] Failed")


def job_hard_delete() -> None:
    """
    Permanently delete documents that have been soft-deleted for 30+ days.
    Also purges associated storage objects.
    Runs daily at 03:00 during low-traffic window.
    """
    import sqlalchemy
    from sqlalchemy import text

    log.info("[HardDelete] Starting 30-day trash purge...")
    try:
        db_url = os.environ.get("DATABASE_URL")
        if not db_url:
            log.error("[HardDelete] DATABASE_URL not set — skipping")
            return

        engine = sqlalchemy.create_engine(db_url)
        with engine.begin() as conn:
            rows = conn.execute(
                text(
                    "SELECT id::text, storage_uri FROM documents "
                    "WHERE deleted_at IS NOT NULL "
                    "  AND deleted_at < now() - interval '30 days'"
                )
            ).fetchall()

            if not rows:
                log.info("[HardDelete] No documents to purge")
                return

            from parser_api.services.storage_service import get_storage_service
            storage = get_storage_service()

            purged = 0
            for row in rows:
                if row.storage_uri:
                    try:
                        storage.delete_object(row.storage_uri)
                    except Exception as e:
                        log.warning("[HardDelete] Storage delete failed for %s: %s", row.id, e)

                conn.execute(
                    text("DELETE FROM documents WHERE id = :doc_id::uuid"),
                    {"doc_id": row.id},
                )
                purged += 1

        log.info("[HardDelete] Purged %d documents", purged)
    except Exception:
        log.exception("[HardDelete] Failed")


# ---------------------------------------------------------------------------
# Scheduler setup
# ---------------------------------------------------------------------------


def main() -> None:
    scheduler = BlockingScheduler(timezone=_TZ)

    # Guardian — daily 07:00 (security brief ready before business hours)
    guardian_hour = int(os.environ.get("GUARDIAN_HOUR", "7"))
    scheduler.add_job(job_guardian, "cron", hour=guardian_hour, minute=0, id="guardian")

    # Customer Success / proactive — daily 09:00
    cs_hour = int(os.environ.get("CS_PROACTIVE_HOUR", "9"))
    scheduler.add_job(job_cs_proactive, "cron", hour=cs_hour, minute=0, id="cs_proactive")

    # Customer Success / reactive — every 30 min, 08:00–20:00
    scheduler.add_job(
        job_cs_reactive, "cron",
        hour="8-20", minute="*/30",
        id="cs_reactive",
    )

    # Product — every Sunday 08:00
    scheduler.add_job(
        job_product, "cron",
        day_of_week="sun", hour=8, minute=0,
        id="product",
    )

    # Creative — every Sunday 10:00
    scheduler.add_job(
        job_creative, "cron",
        day_of_week="sun", hour=10, minute=0,
        id="creative",
    )

    # Hard delete — daily 03:00, purge docs soft-deleted 30+ days ago
    scheduler.add_job(
        job_hard_delete, "cron",
        hour=3, minute=0,
        id="hard_delete",
    )

    # Chief Agent brief — daily 11:00, AFTER all 4 operational agents have run
    chief_hour = int(os.environ.get("CHIEF_AGENT_HOUR", "11"))
    scheduler.add_job(
        job_chief_brief, "cron",
        hour=chief_hour, minute=0,
        id="chief_brief",
    )

    log.info(
        "Scheduler started. Jobs: "
        "guardian (daily %02d:00), "
        "cs_proactive (daily %02d:00), "
        "cs_reactive (every 30m 08-20), "
        "product (Sun 08:00), "
        "creative (Sun 10:00), "
        "hard_delete (daily 03:00), "
        "chief_brief (daily %02d:00)",
        guardian_hour, cs_hour, chief_hour,
    )
    scheduler.start()


if __name__ == "__main__":
    main()
