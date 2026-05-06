"""Beacon Control Room — Streamlit HITL dashboard (Phase 9.5, Chief Agent redesign)."""
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
    elif t == "chief_task_result":
        return (
            f"🧠 Chief Task: **{draft.get('task_type', '?')}**\n\n"
            f"> {draft.get('description_he', '')}\n\n"
            f"{draft.get('result_he', '')}"
        )
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
# Chief Agent helpers
# ---------------------------------------------------------------------------


def _fetch_today_brief() -> dict | None:
    try:
        with engine.connect() as conn:
            row = conn.execute(
                text(
                    "SELECT content_he, citations, generated_at, model "
                    "FROM chief_briefs WHERE brief_date = CURRENT_DATE"
                )
            ).fetchone()
        if not row:
            return None
        return {
            "content_he": row.content_he,
            "citations": row.citations or [],
            "generated_at": row.generated_at,
            "model": row.model,
        }
    except Exception:
        return None


def _fetch_conversations() -> list:
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text(
                    "SELECT DISTINCT ON (conversation_id) "
                    "conversation_id::text, LEFT(content_he, 60) AS preview, created_at "
                    "FROM chief_conversations "
                    "ORDER BY conversation_id, created_at DESC "
                    "LIMIT 20"
                )
            ).fetchall()
        return [{"conversation_id": r.conversation_id, "preview": r.preview,
                 "created_at": r.created_at} for r in rows]
    except Exception:
        return []


def _fetch_conversation_messages(conversation_id: str) -> list:
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text(
                    "SELECT role, content_he, citations, created_at "
                    "FROM chief_conversations "
                    "WHERE conversation_id = :cid "
                    "ORDER BY created_at ASC"
                ),
                {"cid": conversation_id},
            ).fetchall()
        return [
            {
                "role": r.role,
                "content_he": r.content_he,
                "citations": r.citations or [],
                "created_at": r.created_at,
            }
            for r in rows
        ]
    except Exception:
        return []


def _fetch_open_initiatives() -> list:
    try:
        with engine.connect() as conn:
            rows = conn.execute(
                text(
                    "SELECT id::text, target_agent, title_he, status, last_check_at "
                    "FROM initiatives "
                    "WHERE status NOT IN ('completed', 'cancelled') "
                    "ORDER BY created_at DESC LIMIT 30"
                )
            ).fetchall()
        return [dict(r._mapping) for r in rows]
    except Exception:
        return []


def _render_citations(citations: list) -> None:
    if not citations:
        return
    with st.expander(f"📎 {len(citations)} ציטוטים", expanded=False):
        for c in citations:
            agent = c.get("source_agent", "?")
            draft_id = c.get("draft_id", "?")
            st.markdown(f"- **{agent}** · `{draft_id[:12]}…`")


# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

tab_chief, tab_guardian, tab_cs, tab_product, tab_creative = st.tabs([
    "🧠 Chief Agent",
    "🛡️ Guardian",
    "💼 Customer Success",
    "📊 Product",
    "✨ Creative",
])

# ---- CHIEF AGENT -----------------------------------------------------------
with tab_chief:
    col_main, col_right = st.columns([3, 1])

    with col_right:
        # ── Initiatives side panel ──
        st.subheader("📌 יוזמות פתוחות")
        initiatives = _fetch_open_initiatives()
        if not initiatives:
            st.info("אין יוזמות פתוחות.")
        else:
            status_emoji = {
                "open": "🔵", "in_progress": "🟡",
                "waiting_on_agent": "🟠", "completed": "✅", "cancelled": "🔴",
            }
            for init in initiatives:
                emoji = status_emoji.get(init["status"], "⚪")
                st.markdown(
                    f"{emoji} **{init['title_he']}**  \n"
                    f"_{init['target_agent']}_ · {init['status']}"
                )
                st.divider()

    with col_main:
        # ── Daily brief at top ──
        st.subheader("📋 בריף יומי")
        brief = _fetch_today_brief()
        if brief:
            st.caption(
                f"נוצר: {brief['generated_at'].strftime('%H:%M')} · מודל: {brief.get('model', '?')}"
            )
            st.markdown(brief["content_he"])
            _render_citations(brief["citations"])
        else:
            st.info("הבריף היומי טרם נוצר.")
            if st.button("⚡ צור בריף עכשיו", type="primary"):
                with st.spinner("מייצר בריף…"):
                    try:
                        from agents.graphs.chief.briefs import generate_daily_brief
                        result = generate_daily_brief()
                        st.success(
                            f"בריף נוצר — {result['citations_count']} ציטוטים, "
                            f"grounding={'✅' if result['grounding_ok'] else '⚠️'}"
                        )
                        st.rerun()
                    except Exception as e:
                        st.error(f"שגיאה: {e}")

        st.divider()

        # ── Chat interface ──
        st.subheader("💬 שיחה עם ה-Chief")

        # Conversation selector
        conversations = _fetch_conversations()
        conv_options = ["➕ שיחה חדשה"] + [
            f"{c['created_at'].strftime('%m-%d %H:%M')} — {c['preview']}"
            for c in conversations
        ]
        selected_idx = st.selectbox("שיחות קודמות", range(len(conv_options)),
                                    format_func=lambda i: conv_options[i])

        if selected_idx == 0:
            # New conversation
            if "chief_conv_id" not in st.session_state or st.session_state.get("_new_conv"):
                st.session_state["chief_conv_id"] = str(uuid.uuid4())
                st.session_state["_new_conv"] = False
            conversation_id = st.session_state["chief_conv_id"]
            messages = []
        else:
            conversation_id = conversations[selected_idx - 1]["conversation_id"]
            messages = _fetch_conversation_messages(conversation_id)

        # Render history
        for msg in messages:
            with st.chat_message("user" if msg["role"] == "user" else "assistant"):
                st.markdown(msg["content_he"])
                _render_citations(msg["citations"])

        # Input
        user_input = st.chat_input("שאל את ה-Chief…")
        if user_input and user_input.strip():
            with st.chat_message("user"):
                st.markdown(user_input)

            with st.chat_message("assistant"):
                with st.spinner("ה-Chief חושב…"):
                    try:
                        from agents.graphs.chief.chat import handle_chat_turn
                        result = handle_chat_turn(conversation_id, user_input.strip())
                        reply = result["reply_he"]
                        citations = result["citations"]
                        st.markdown(reply)
                        _render_citations(citations)
                        if not result["grounding_ok"]:
                            st.warning("⚠️ חלק מהטענות ללא ציטוט — תוצאות ייתכן שאינן מעוגנות.")
                    except Exception as e:
                        st.error(f"שגיאה: {e}")
            st.rerun()


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
                    "WHERE metrics->>'brief_type' IS NULL "
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
