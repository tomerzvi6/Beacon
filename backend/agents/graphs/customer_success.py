"""
Customer Success agent — merged proactive + reactive user-facing role.

Proactive (daily 09:00):
  gather_proactive → prioritize → draft_nudges → draft_cohort_summary → propose_batch

Reactive (every 30 min):
  gather_tickets → rag_retrieve → draft_reply → propose_reply
"""
from typing import TypedDict

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy import text
from sqlalchemy.orm import Session

from agents.db import get_engine
from shared.models import AgentRun, SupportTicket

# ---------------------------------------------------------------------------
# Shared system prompt (cached — same across both modes)
# ---------------------------------------------------------------------------

_CS_SYSTEM = (
    "אתה נציג Customer Success של אפליקציית Beacon לניהול טיפול בסרטן. "
    "תפקידך: לתמוך במשפחות המטפלות בחום, מקצועיות ובעברית תקנית. "
    "לעולם אל תספק ייעוץ רפואי — הפנה תמיד לרופא המטפל. "
    "אל תכלול PHI (שמות חולים, מספרי מטופל) בתגובות שלך."
)

# ---------------------------------------------------------------------------
# PROACTIVE mode — daily batch
# ---------------------------------------------------------------------------


class ProactiveState(TypedDict):
    unclaimed_tasks: list[dict]
    at_risk_households: list[dict]
    top_task: dict | None
    push_body_he: str
    cohort_summary: str
    run_id: str


def _gather_proactive(state: ProactiveState) -> ProactiveState:
    with get_engine().connect() as conn:
        tasks = conn.execute(
            text(
                "SELECT task_id::text, household_id::text, category, age_hours, due_at "
                "FROM v_unclaimed_tasks_age WHERE age_hours > 48 "
                "ORDER BY age_hours DESC LIMIT 50"
            )
        ).fetchall()

        at_risk = conn.execute(
            text(
                "SELECT household_id::text, days_since_activity, total_tasks "
                "FROM v_user_engagement "
                "WHERE days_since_activity > 7 "
                "ORDER BY days_since_activity DESC LIMIT 20"
            )
        ).fetchall()

    state["unclaimed_tasks"] = [dict(r._mapping) for r in tasks]
    state["at_risk_households"] = [dict(r._mapping) for r in at_risk]
    return state


def _prioritize(state: ProactiveState) -> ProactiveState:
    priority = {"medication": 0, "appointment": 1, "test": 2, "admin": 3}
    tasks = state["unclaimed_tasks"]
    if not tasks:
        state["top_task"] = None
        return state
    state["top_task"] = sorted(
        tasks, key=lambda t: (priority.get(t["category"], 99), -t["age_hours"])
    )[0]
    return state


def _draft_nudge(state: ProactiveState) -> ProactiveState:
    if not state["top_task"]:
        state["push_body_he"] = ""
        return state

    task = state["top_task"]
    client = Anthropic()
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=200,
        system=[{"type": "text", "text": _CS_SYSTEM, "cache_control": {"type": "ephemeral"}}],
        tools=[{
            "name": "push_nudge",
            "description": "Short Hebrew push notification nudging caregiver to act",
            "input_schema": {
                "type": "object",
                "properties": {"body_he": {"type": "string", "maxLength": 80}},
                "required": ["body_he"],
            },
        }],
        messages=[{
            "role": "user",
            "content": (
                f"כתוב הודעת push עדינה ומעודדת עבור משימה שלא טופלה "
                f"{int(task['age_hours'])} שעות. קטגוריה: {task['category']}."
            ),
        }],
    )

    for block in message.content:
        if hasattr(block, "type") and block.type == "tool_use":
            state["push_body_he"] = block.input.get("body_he", "")
            break
    return state


def _draft_cohort_summary(state: ProactiveState) -> ProactiveState:
    unclaimed = len(state["unclaimed_tasks"])
    at_risk = len(state["at_risk_households"])

    if unclaimed == 0 and at_risk == 0:
        state["cohort_summary"] = ""
        return state

    client = Anthropic()
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=400,
        system=[{"type": "text", "text": _CS_SYSTEM, "cache_control": {"type": "ephemeral"}}],
        tools=[{
            "name": "cohort_brief",
            "description": "Daily cohort health brief in Hebrew Markdown",
            "input_schema": {
                "type": "object",
                "properties": {
                    "markdown_he": {"type": "string"},
                    "urgent_count": {"type": "integer"},
                },
                "required": ["markdown_he", "urgent_count"],
            },
        }],
        messages=[{
            "role": "user",
            "content": (
                f"סכם את מצב המשתמשים:\n"
                f"- משימות לא מטופלות >48 שעות: {unclaimed}\n"
                f"- משקי בית שלא פעילים 7+ ימים: {at_risk}\n"
                "כתוב בריף יומי קצר בעברית עבור Tomer."
            ),
        }],
    )

    for block in message.content:
        if hasattr(block, "type") and block.type == "tool_use":
            state["cohort_summary"] = block.input.get("markdown_he", "")
            break
    return state


def _propose_proactive(state: ProactiveState) -> ProactiveState:
    has_nudge = bool(state["top_task"] and state["push_body_he"])
    has_summary = bool(state["cohort_summary"])

    if not has_nudge and not has_summary:
        return state

    run = AgentRun(
        agent_name="customer_success",
        status="awaiting_approval",
        input_summary={
            "mode": "proactive",
            "unclaimed_count": len(state["unclaimed_tasks"]),
            "at_risk_count": len(state["at_risk_households"]),
        },
        output_draft={
            "type": "push" if has_nudge else "cs_daily_brief",
            "user_id": state["top_task"]["household_id"] if has_nudge else None,
            "body_he": state["push_body_he"] if has_nudge else None,
            "cohort_summary_he": state["cohort_summary"],
        },
    )

    with Session(get_engine()) as session:
        session.add(run)
        session.commit()
        state["run_id"] = str(run.id)

    return state


def build_proactive_graph() -> StateGraph:
    g = StateGraph(ProactiveState)
    g.add_node("gather", _gather_proactive)
    g.add_node("prioritize", _prioritize)
    g.add_node("draft_nudge", _draft_nudge)
    g.add_node("draft_cohort_summary", _draft_cohort_summary)
    g.add_node("propose", _propose_proactive)
    g.set_entry_point("gather")
    g.add_edge("gather", "prioritize")
    g.add_edge("prioritize", "draft_nudge")
    g.add_edge("draft_nudge", "draft_cohort_summary")
    g.add_edge("draft_cohort_summary", "propose")
    g.add_edge("propose", END)
    return g.compile()


def run_customer_success_proactive() -> dict:
    return build_proactive_graph().invoke({
        "unclaimed_tasks": [],
        "at_risk_households": [],
        "top_task": None,
        "push_body_he": "",
        "cohort_summary": "",
        "run_id": "",
    })


# ---------------------------------------------------------------------------
# REACTIVE mode — on new support tickets
# ---------------------------------------------------------------------------


class ReactiveState(TypedDict):
    tickets: list[dict]
    current_ticket: dict | None
    relevant_docs: list[str]
    draft_response: str
    needs_human: bool
    run_id: str


def _gather_tickets(state: ReactiveState) -> ReactiveState:
    with get_engine().connect() as conn:
        rows = conn.execute(
            text(
                "SELECT id::text, user_id::text, subject, body, created_at "
                "FROM v_support_inbox ORDER BY created_at ASC LIMIT 10"
            )
        ).fetchall()

    state["tickets"] = [dict(r._mapping) for r in rows]
    state["current_ticket"] = state["tickets"][0] if state["tickets"] else None
    return state


def _rag_retrieve(state: ReactiveState) -> ReactiveState:
    if not state["current_ticket"]:
        state["relevant_docs"] = []
        return state

    with get_engine().connect() as conn:
        rows = conn.execute(
            text("SELECT content FROM doc_chunks ORDER BY created_at DESC LIMIT 5")
        ).fetchall()

    state["relevant_docs"] = [r.content for r in rows]
    return state


def _draft_reply(state: ReactiveState) -> ReactiveState:
    if not state["current_ticket"]:
        state["draft_response"] = ""
        state["needs_human"] = False
        return state

    ticket = state["current_ticket"]
    docs_ctx = "\n\n---\n\n".join(state["relevant_docs"][:3]) or "אין מסמכים רלוונטיים."

    client = Anthropic()
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=600,
        system=[{"type": "text", "text": _CS_SYSTEM, "cache_control": {"type": "ephemeral"}}],
        tools=[{
            "name": "support_reply",
            "description": "Draft support reply in Hebrew",
            "input_schema": {
                "type": "object",
                "properties": {
                    "body_he": {"type": "string"},
                    "needs_human": {
                        "type": "boolean",
                        "description": "True if requires human escalation",
                    },
                },
                "required": ["body_he", "needs_human"],
            },
        }],
        messages=[{
            "role": "user",
            "content": (
                f"מסמכי עזרה:\n{docs_ctx}\n\n---\n"
                f"כותרת: {ticket['subject']}\nהודעה: {ticket['body']}"
            ),
        }],
    )

    for block in message.content:
        if hasattr(block, "type") and block.type == "tool_use":
            result = block.input
            state["needs_human"] = result.get("needs_human", False)
            state["draft_response"] = result.get("body_he", "")
            break

    return state


def _propose_reply(state: ReactiveState) -> ReactiveState:
    if not state["current_ticket"]:
        return state

    ticket = state["current_ticket"]

    with Session(get_engine()) as session:
        t = session.query(SupportTicket).filter(SupportTicket.id == ticket["id"]).first()
        if t:
            if state["needs_human"]:
                t.status = "needs_human"
                session.commit()
                return state
            t.status = "drafted"
            t.draft_response = state["draft_response"]

        if not state["draft_response"]:
            session.commit()
            return state

        run = AgentRun(
            agent_name="customer_success",
            status="awaiting_approval",
            input_summary={
                "mode": "reactive",
                "ticket_id": ticket["id"],
                "subject_preview": ticket["subject"][:60],
            },
            output_draft={
                "type": "support_reply",
                "ticket_id": ticket["id"],
                "body_he": state["draft_response"],
            },
        )
        session.add(run)
        session.flush()

        if t:
            t.draft_run_id = run.id

        session.commit()
        state["run_id"] = str(run.id)

    return state


def build_reactive_graph() -> StateGraph:
    g = StateGraph(ReactiveState)
    g.add_node("gather_tickets", _gather_tickets)
    g.add_node("rag_retrieve", _rag_retrieve)
    g.add_node("draft_reply", _draft_reply)
    g.add_node("propose_reply", _propose_reply)
    g.set_entry_point("gather_tickets")
    g.add_edge("gather_tickets", "rag_retrieve")
    g.add_edge("rag_retrieve", "draft_reply")
    g.add_edge("draft_reply", "propose_reply")
    g.add_edge("propose_reply", END)
    return g.compile()


def run_customer_success_reactive() -> dict:
    return build_reactive_graph().invoke({
        "tickets": [],
        "current_ticket": None,
        "relevant_docs": [],
        "draft_response": "",
        "needs_human": False,
        "run_id": "",
    })
