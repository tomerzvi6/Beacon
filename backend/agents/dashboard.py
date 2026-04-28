"""Beacon Control Room — Streamlit HITL dashboard."""
import os
import uuid

import streamlit as st
from sqlalchemy import text

from agents.db import get_engine
from agents.executor import execute_approved_run, reject_run
from shared.models import AgentMetricsSnapshot, AgentRun, AuditLog

st.set_page_config(page_title="Beacon Control Room", layout="wide", page_icon="🔦")
st.title("Beacon — Control Room")

engine = get_engine()

APPROVER_ID = os.environ.get("DASHBOARD_APPROVER_ID", "00000000-0000-0000-0000-000000000001")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _status_badge(status: str) -> str:
    colors = {
        "awaiting_approval": "🟡",
        "approved": "🟢",
        "rejected": "🔴",
        "executed": "✅",
        "failed": "❌",
        "running": "🔵",
    }
    return f"{colors.get(status, '⚪')} {status}"


def _agent_label(name: str) -> str:
    labels = {
        "nudger": "📣 Nudger",
        "support": "💬 Support",
        "analyst": "📊 Analyst",
    }
    return labels.get(name, name)


def _draft_summary(draft: dict) -> str:
    t = draft.get("type", "unknown")
    if t == "push":
        return f"📱 Push → user `{draft.get('user_id', '')[:8]}…`\n\n> {draft.get('body_he', '')}"
    elif t == "support_reply":
        return f"✉️ Reply → ticket `{draft.get('ticket_id', '')[:8]}…`\n\n> {draft.get('body_he', '')}"
    elif t == "weekly_report":
        preview = (draft.get("markdown") or "")[:300]
        return f"📄 Weekly Report\n\n{preview}…"
    return str(draft)


# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

tab_inbox, tab_activity, tab_metrics, tab_health = st.tabs(
    ["📥 Inbox", "📋 Activity", "📊 Metrics", "🩺 Health"]
)

# ---- INBOX -----------------------------------------------------------------
with tab_inbox:
    st.subheader("Awaiting Approval")

    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT id, agent_name, input_summary, output_draft, started_at "
                "FROM agent_runs WHERE status = 'awaiting_approval' "
                "ORDER BY started_at DESC"
            )
        ).fetchall()

    if not rows:
        st.info("No drafts awaiting approval.")
    else:
        for row in rows:
            run_id = str(row.id)
            with st.expander(
                f"{_agent_label(row.agent_name)}  —  {row.started_at.strftime('%Y-%m-%d %H:%M')}",
                expanded=True,
            ):
                col_left, col_right = st.columns([3, 1])

                with col_left:
                    st.caption("Input summary")
                    st.json(row.input_summary)
                    st.caption("Draft action")
                    st.markdown(_draft_summary(row.output_draft))

                with col_right:
                    # Edit draft before approving
                    edited_body = None
                    draft = row.output_draft
                    if draft.get("type") in ("push", "support_reply"):
                        edited_body = st.text_area(
                            "Edit text (optional)",
                            value=draft.get("body_he", ""),
                            key=f"edit_{run_id}",
                            height=100,
                        )

                    approve_col, reject_col = st.columns(2)
                    with approve_col:
                        if st.button("✅ Approve", key=f"approve_{run_id}", type="primary"):
                            try:
                                if edited_body and edited_body != draft.get("body_he"):
                                    draft["body_he"] = edited_body
                                execute_approved_run(run_id, APPROVER_ID, draft)
                                st.success("Executed!")
                                st.rerun()
                            except Exception as e:
                                st.error(str(e))
                    with reject_col:
                        if st.button("❌ Reject", key=f"reject_{run_id}"):
                            reject_run(run_id, APPROVER_ID)
                            st.warning("Rejected.")
                            st.rerun()

# ---- ACTIVITY --------------------------------------------------------------
with tab_activity:
    st.subheader("Agent Run History")

    agent_filter = st.selectbox("Filter by agent", ["all", "nudger", "support", "analyst"])
    status_filter = st.selectbox(
        "Filter by status",
        ["all", "executed", "rejected", "failed", "awaiting_approval"],
    )

    where_clauses = []
    if agent_filter != "all":
        where_clauses.append(f"agent_name = '{agent_filter}'")
    if status_filter != "all":
        where_clauses.append(f"status = '{status_filter}'")
    where_sql = ("WHERE " + " AND ".join(where_clauses)) if where_clauses else ""

    with engine.connect() as conn:
        rows = conn.execute(
            text(
                f"SELECT id, agent_name, status, started_at, finished_at, "
                f"input_summary, execution_result "
                f"FROM agent_runs {where_sql} ORDER BY started_at DESC LIMIT 100"
            )
        ).fetchall()

    if not rows:
        st.info("No runs found.")
    else:
        for row in rows:
            with st.expander(
                f"{_agent_label(row.agent_name)} | {_status_badge(row.status)} | "
                f"{row.started_at.strftime('%Y-%m-%d %H:%M')}"
            ):
                st.json({
                    "id": str(row.id),
                    "status": row.status,
                    "input_summary": row.input_summary,
                    "result": row.execution_result,
                })

# ---- METRICS ---------------------------------------------------------------
with tab_metrics:
    st.subheader("Weekly Reports")

    with engine.connect() as conn:
        snaps = conn.execute(
            text(
                "SELECT week_starting, report_markdown, metrics, created_at "
                "FROM agent_metrics_snapshots ORDER BY week_starting DESC LIMIT 10"
            )
        ).fetchall()

    if not snaps:
        st.info("No weekly snapshots yet.")
    else:
        for snap in snaps:
            with st.expander(f"Week of {snap.week_starting.strftime('%Y-%m-%d')}"):
                if snap.report_markdown:
                    st.markdown(snap.report_markdown)
                else:
                    st.json(snap.metrics)

# ---- HEALTH ----------------------------------------------------------------
with tab_health:
    st.subheader("Scheduler Health")

    with engine.connect() as conn:
        agents = ["nudger", "support", "analyst"]
        for agent in agents:
            row = conn.execute(
                text(
                    "SELECT status, started_at FROM agent_runs "
                    "WHERE agent_name = :name ORDER BY started_at DESC LIMIT 1"
                ),
                {"name": agent},
            ).fetchone()

            if row:
                delta = row.started_at
                st.metric(
                    label=_agent_label(agent),
                    value=row.status,
                    delta=f"last run: {row.started_at.strftime('%Y-%m-%d %H:%M')}",
                )
            else:
                st.metric(label=_agent_label(agent), value="never run")
