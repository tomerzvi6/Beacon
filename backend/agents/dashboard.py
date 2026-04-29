"""Beacon Control Room — Streamlit HITL dashboard (Phase 7, 4-agent redesign)."""
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
# Agent metadata
# ---------------------------------------------------------------------------

AGENTS = {
    "guardian":          {"icon": "🛡️",  "label": "Guardian",          "cadence": "Daily 07:00"},
    "customer_success":  {"icon": "💼",  "label": "Customer Success",   "cadence": "Daily 09:00 + 30 min reactive"},
    "product":           {"icon": "📊",  "label": "Product",            "cadence": "Weekly (Sunday 08:00)"},
    "creative":          {"icon": "✨",  "label": "Creative",           "cadence": "Weekly (Sunday 10:00) + on-demand"},
}


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
    meta = AGENTS.get(name, {})
    return f"{meta.get('icon', '')} {meta.get('label', name)}"


def _draft_summary(draft: dict) -> str:
    t = draft.get("type", "unknown")
    if t == "push":
        return f"📱 Push → household `{(draft.get('user_id') or '')[:8]}…`\n\n> {draft.get('body_he', '')}"
    elif t == "support_reply":
        return f"✉️ Reply → ticket `{(draft.get('ticket_id') or '')[:8]}…`\n\n> {draft.get('body_he', '')}"
    elif t in ("weekly_report", "product_report"):
        preview = (draft.get("markdown") or "")[:400]
        return f"📄 Product Report\n\n{preview}…"
    elif t == "security_brief":
        preview = (draft.get("markdown") or "")[:400]
        findings = draft.get("findings", [])
        crit = sum(1 for f in findings if f.get("severity") == "critical")
        high = sum(1 for f in findings if f.get("severity") == "high")
        return (
            f"🛡️ Security Brief — **{len(findings)} findings** "
            f"({crit} critical, {high} high)\n\n{preview}…"
        )
    elif t == "content_draft":
        pieces = draft.get("pieces", [])
        theme = draft.get("calendar_week_theme_he", "")
        lines = [f"✨ Content Draft — {len(pieces)} pieces"]
        if theme:
            lines.append(f"\n> {theme}")
        for p in pieces[:3]:
            lines.append(f"\n**{p.get('slot', '')}:** {p.get('copy_he', '')}")
        if len(pieces) > 3:
            lines.append(f"\n_...{len(pieces) - 3} more_")
        return "\n".join(lines)
    elif t == "cs_daily_brief":
        return f"💼 CS Daily Brief\n\n{draft.get('cohort_summary_he', '')}"
    return str(draft)[:300]


def _fetch_pending(agent_name: str | None = None) -> list:
    params: dict = {}
    where = "WHERE status = 'awaiting_approval'"
    if agent_name:
        where += " AND agent_name = :agent_name"
        params["agent_name"] = agent_name
    with engine.connect() as conn:
        return conn.execute(
            text(
                f"SELECT id, agent_name, input_summary, output_draft, started_at "
                f"FROM agent_runs {where} ORDER BY started_at DESC"
            ),
            params,
        ).fetchall()


def _fetch_recent(agent_name: str | None = None, limit: int = 50) -> list:
    params: dict = {"lim": limit}
    where = ""
    if agent_name:
        where = "WHERE agent_name = :agent_name"
        params["agent_name"] = agent_name
    with engine.connect() as conn:
        return conn.execute(
            text(
                f"SELECT id, agent_name, status, started_at, finished_at, "
                f"input_summary, execution_result "
                f"FROM agent_runs {where} ORDER BY started_at DESC LIMIT :lim"
            ),
            params,
        ).fetchall()


def _last_run(agent_name: str):
    with engine.connect() as conn:
        return conn.execute(
            text(
                "SELECT status, started_at FROM agent_runs "
                "WHERE agent_name = :name ORDER BY started_at DESC LIMIT 1"
            ),
            {"name": agent_name},
        ).fetchone()


# ---------------------------------------------------------------------------
# Shared inbox widget — renders pending drafts with approve/reject
# ---------------------------------------------------------------------------


def _render_inbox(rows: list) -> None:
    if not rows:
        st.info("No drafts awaiting approval.")
        return

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
                st.caption("Draft")
                st.markdown(_draft_summary(row.output_draft))

            with col_right:
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
                                draft = {**draft, "body_he": edited_body}
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


def _render_activity(rows: list) -> None:
    if not rows:
        st.info("No runs found.")
        return
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


# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

tab_digest, tab_guardian, tab_cs, tab_product, tab_creative = st.tabs([
    "🗞️ Digest",
    "🛡️ Guardian",
    "💼 Customer Success",
    "📊 Product",
    "✨ Creative",
])

# ---- DIGEST ----------------------------------------------------------------
with tab_digest:
    st.subheader("Global Digest")

    # Pending counts per agent
    with engine.connect() as conn:
        pending_counts = conn.execute(
            text(
                "SELECT agent_name, COUNT(*) AS cnt "
                "FROM agent_runs WHERE status = 'awaiting_approval' "
                "GROUP BY agent_name"
            )
        ).fetchall()

    pending_map = {r.agent_name: r.cnt for r in pending_counts}
    total_pending = sum(pending_map.values())

    if total_pending:
        st.warning(f"**{total_pending} draft(s) awaiting approval**")
    else:
        st.success("All clear — no pending approvals.")

    cols = st.columns(len(AGENTS))
    for col, (agent_name, meta) in zip(cols, AGENTS.items()):
        last = _last_run(agent_name)
        with col:
            st.metric(
                label=f"{meta['icon']} {meta['label']}",
                value=f"{pending_map.get(agent_name, 0)} pending",
                delta=f"Last: {last.started_at.strftime('%m-%d %H:%M')}" if last else "Never run",
            )

    st.divider()

    # Today's guardian brief (if any)
    st.subheader("Latest Security Brief")
    with engine.connect() as conn:
        brief_row = conn.execute(
            text(
                "SELECT output_draft, started_at FROM agent_runs "
                "WHERE agent_name = 'guardian' "
                "ORDER BY started_at DESC LIMIT 1"
            )
        ).fetchone()

    if brief_row:
        brief_md = brief_row.output_draft.get("markdown", "")
        st.caption(f"Run: {brief_row.started_at.strftime('%Y-%m-%d %H:%M')}")
        st.markdown(brief_md or "_No brief generated._")
    else:
        st.info("Guardian hasn't run yet.")

    st.divider()

    # All pending drafts in one view
    st.subheader("📥 All Pending Approvals")
    all_pending = _fetch_pending()
    _render_inbox(all_pending)


# ---- GUARDIAN --------------------------------------------------------------
with tab_guardian:
    st.subheader("🛡️ Guardian — Security & Privacy Auditor")
    st.caption(f"Cadence: {AGENTS['guardian']['cadence']}")

    sub_inbox, sub_activity = st.tabs(["📥 Inbox", "📋 Activity"])

    with sub_inbox:
        _render_inbox(_fetch_pending("guardian"))

    with sub_activity:
        rows = _fetch_recent("guardian")
        _render_activity(rows)

        # Expandable: latest full security brief
        if rows:
            latest = rows[0]
            with engine.connect() as conn:
                full = conn.execute(
                    text("SELECT output_draft FROM agent_runs WHERE id = :rid"),
                    {"rid": latest.id},
                ).fetchone()
            if full and full.output_draft.get("type") == "security_brief":
                with st.expander("Latest brief (full)"):
                    st.markdown(full.output_draft.get("markdown", ""))
                    st.json({"rls_results": full.output_draft.get("rls_results", {}),
                             "findings": full.output_draft.get("findings", [])})


# ---- CUSTOMER SUCCESS -------------------------------------------------------
with tab_cs:
    st.subheader("💼 Customer Success")
    st.caption(f"Cadence: {AGENTS['customer_success']['cadence']}")

    sub_inbox, sub_activity = st.tabs(["📥 Inbox", "📋 Activity"])

    with sub_inbox:
        _render_inbox(_fetch_pending("customer_success"))

    with sub_activity:
        _render_activity(_fetch_recent("customer_success"))


# ---- PRODUCT ---------------------------------------------------------------
with tab_product:
    st.subheader("📊 Product — Usage Analyst & Feature Scout")
    st.caption(f"Cadence: {AGENTS['product']['cadence']}")

    sub_inbox, sub_reports = st.tabs(["📥 Inbox", "📈 Reports"])

    with sub_inbox:
        _render_inbox(_fetch_pending("product"))

    with sub_reports:
        with engine.connect() as conn:
            snaps = conn.execute(
                text(
                    "SELECT week_starting, report_markdown, metrics, created_at "
                    "FROM agent_metrics_snapshots "
                    "WHERE metrics->>'brief_type' IS NULL "  # exclude security/content acks
                    "ORDER BY week_starting DESC LIMIT 10"
                )
            ).fetchall()

        if not snaps:
            st.info("No product reports yet.")
        else:
            for snap in snaps:
                with st.expander(f"Week of {snap.week_starting.strftime('%Y-%m-%d')}"):
                    if snap.report_markdown:
                        st.markdown(snap.report_markdown)
                    else:
                        st.json(snap.metrics)


# ---- CREATIVE --------------------------------------------------------------
with tab_creative:
    st.subheader("✨ Creative — Content & Copy")
    st.caption(f"Cadence: {AGENTS['creative']['cadence']}")

    sub_inbox, sub_activity, sub_demand = st.tabs(["📥 Inbox", "📋 Activity", "🎯 On-Demand"])

    with sub_inbox:
        _render_inbox(_fetch_pending("creative"))

    with sub_activity:
        _render_activity(_fetch_recent("creative"))

    with sub_demand:
        st.markdown("Trigger a one-off content request (runs synchronously).")
        request_text = st.text_area(
            "Content request (Hebrew or English)",
            placeholder="כתוב טקסט empty state לרשימת תרופות ריקה...",
            height=100,
        )
        if st.button("🚀 Run Creative On-Demand", type="primary"):
            if not request_text.strip():
                st.error("Please enter a content request.")
            else:
                with st.spinner("Running Creative agent..."):
                    try:
                        from agents.graphs.creative.graph import run_creative_on_demand
                        result = run_creative_on_demand(request_text.strip())
                        run_id = result.get("run_id")
                        if run_id:
                            st.success(f"Draft created — run_id: `{run_id}`. Check Inbox above.")
                        else:
                            st.warning("Agent ran but produced no draft.")
                    except Exception as e:
                        st.error(f"Error: {e}")
