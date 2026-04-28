"""
The ONLY module with outbound credentials (APNs, email).
No agent calls this directly — only Streamlit dashboard after human approval.
"""
import json
import os
import time
import uuid
from datetime import datetime, timezone

import httpx
from jose import jwt

from agents.db import get_session
from shared.models import AgentRun, AuditLog


def execute_approved_run(run_id: str, approver_id: str, edited_draft: dict | None = None) -> dict:
    """
    Dispatch an approved agent_run to its executor.
    Updates agent_runs.status and writes to audit_log.
    """
    with get_session() as session:
        run = session.query(AgentRun).filter(AgentRun.id == run_id).first()
        if not run:
            raise ValueError(f"AgentRun {run_id} not found")
        if run.status != "awaiting_approval":
            raise ValueError(f"Run {run_id} is not awaiting approval (status={run.status})")

        draft = edited_draft or run.output_draft
        draft_type = draft.get("type")

        try:
            if draft_type == "push":
                result = _send_push(draft["user_id"], draft["body_he"])
            elif draft_type == "support_reply":
                result = _send_support_reply(draft["ticket_id"], draft["body_he"])
            elif draft_type == "weekly_report":
                result = _publish_report(run_id, draft["markdown"])
            else:
                raise ValueError(f"Unknown draft type: {draft_type}")

            run.status = "executed"
            run.approver = uuid.UUID(approver_id)
            run.approved_at = datetime.now(tz=timezone.utc)
            run.execution_result = result

        except Exception as e:
            run.status = "failed"
            run.execution_result = {"error": str(e)}
            session.commit()
            raise

        session.add(AuditLog(
            actor_type="human:tomer",
            actor_id=approver_id,
            action=f"approved:{draft_type}",
            target_table="agent_runs",
            target_id=run.id,
            metadata_={"run_id": run_id, "draft_type": draft_type},
        ))
        session.commit()
        return run.execution_result


def reject_run(run_id: str, approver_id: str) -> None:
    """Mark an agent run as rejected without executing."""
    with get_session() as session:
        run = session.query(AgentRun).filter(AgentRun.id == run_id).first()
        if run:
            run.status = "rejected"
            run.approver = uuid.UUID(approver_id)
            run.approved_at = datetime.now(tz=timezone.utc)
            session.add(AuditLog(
                actor_type="human:tomer",
                actor_id=approver_id,
                action="rejected",
                target_table="agent_runs",
                target_id=run.id,
                metadata_={"run_id": run_id},
            ))
            session.commit()


# ---------------------------------------------------------------------------
# Internal executors — only called by execute_approved_run
# ---------------------------------------------------------------------------


def _send_push(user_id: str, body_he: str) -> dict:
    """Send APNs push notification to a single user."""
    from shared.models import User

    with get_session() as session:
        user = session.query(User).filter(User.id == user_id).first()
        if not user or not user.push_token:
            return {"skipped": "no_push_token", "user_id": user_id}

    key_id = os.environ["APNS_KEY_ID"]
    team_id = os.environ["APNS_TEAM_ID"]
    key_path = os.environ["APNS_AUTH_KEY_PATH"]
    bundle_id = os.environ.get("APNS_BUNDLE_ID", "com.beacon.app")

    with open(key_path) as f:
        private_key = f.read()

    # APNs JWT — expires in 1 hour, re-used within that window
    token = jwt.encode(
        {"iss": team_id, "iat": int(time.time())},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id},
    )

    payload = json.dumps({
        "aps": {
            "alert": {"title": "Beacon", "body": body_he},
            "sound": "default",
        }
    })

    url = f"https://api.push.apple.com/3/device/{user.push_token}"
    with httpx.Client(http2=True) as client:
        response = client.post(
            url,
            content=payload.encode(),
            headers={
                "authorization": f"bearer {token}",
                "apns-topic": bundle_id,
                "apns-push-type": "alert",
                "content-type": "application/json",
            },
        )

    if response.status_code != 200:
        raise RuntimeError(f"APNs error {response.status_code}: {response.text}")

    return {"sent": True, "user_id": user_id}


def _send_support_reply(ticket_id: str, body_he: str) -> dict:
    """Mark support ticket as replied with the drafted response."""
    from shared.models import SupportTicket

    with get_session() as session:
        ticket = session.query(SupportTicket).filter(SupportTicket.id == ticket_id).first()
        if not ticket:
            raise ValueError(f"Ticket {ticket_id} not found")

        ticket.draft_response = body_he
        ticket.status = "replied"
        session.commit()

    # Wire to email provider (SendGrid, Resend, etc.) here in production
    return {"replied": True, "ticket_id": ticket_id}


def _publish_report(run_id: str, markdown: str) -> dict:
    """Save weekly report snapshot — visible in Streamlit Metrics tab."""
    from datetime import timedelta

    from shared.models import AgentMetricsSnapshot

    week_start = datetime.now(tz=timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    # Round to Monday
    week_start -= timedelta(days=week_start.weekday())

    with get_session() as session:
        snap = AgentMetricsSnapshot(
            week_starting=week_start,
            report_markdown=markdown,
            metrics={"published_from_run": run_id},
        )
        session.add(snap)
        session.commit()

    return {"published": True, "week_starting": str(week_start.date())}
