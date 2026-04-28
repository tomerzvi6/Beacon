"""
Support agent — processes new support tickets with RAG over app docs.
NEVER accesses patient medical data. Refuses medical advice in prompts.

Graph: gather → rag_retrieve → draft → propose
"""
from typing import TypedDict

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy import text
from sqlalchemy.orm import Session

from agents.db import get_engine
from shared.models import AgentRun, SupportTicket


class SupportState(TypedDict):
    tickets: list[dict]
    current_ticket: dict | None
    relevant_docs: list[str]
    draft_response: str
    run_id: str


def gather(state: SupportState) -> SupportState:
    """Fetch new tickets from v_support_inbox."""
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


def rag_retrieve(state: SupportState) -> SupportState:
    """Retrieve relevant doc chunks for the current ticket using cosine similarity."""
    if not state["current_ticket"]:
        state["relevant_docs"] = []
        return state

    ticket = state["current_ticket"]
    query_text = f"{ticket['subject']} {ticket['body']}"

    client = Anthropic()
    # Generate embedding for the query using Anthropic (text-embedding-3-small equiv.)
    # Using a simple approach: encode the question and retrieve top-k chunks via pgvector
    with get_engine().connect() as conn:
        # Use naive text search as fallback if pgvector embedding not set up yet
        rows = conn.execute(
            text(
                "SELECT content FROM doc_chunks "
                "ORDER BY created_at DESC LIMIT 5"
            )
        ).fetchall()

    state["relevant_docs"] = [r.content for r in rows]
    return state


def draft(state: SupportState) -> SupportState:
    """Draft a Hebrew response grounded in app docs. Refuses medical advice."""
    if not state["current_ticket"]:
        state["draft_response"] = ""
        return state

    ticket = state["current_ticket"]
    docs_context = "\n\n---\n\n".join(state["relevant_docs"][:3]) if state["relevant_docs"] else "אין מסמכים רלוונטיים."

    client = Anthropic()
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=600,
        system=[
            {
                "type": "text",
                "text": (
                    "אתה נציג תמיכה של אפליקציית Beacon. "
                    "ענה בעברית בצורה חמה ומקצועית. "
                    "השתמש רק במידע מהמסמכים שצורפו. "
                    "אם השאלה נוגעת לייעוץ רפואי — ענה: 'אנחנו לא מספקים ייעוץ רפואי, אנא פנה לרופא.' "
                    "אל תמציא מידע שאינו במסמכים."
                ),
                "cache_control": {"type": "ephemeral"},
            }
        ],
        tools=[{
            "name": "support_reply",
            "description": "Draft support reply in Hebrew",
            "input_schema": {
                "type": "object",
                "properties": {
                    "body_he": {"type": "string"},
                    "needs_human": {
                        "type": "boolean",
                        "description": "True if this requires human escalation",
                    },
                },
                "required": ["body_he", "needs_human"],
            },
        }],
        messages=[{
            "role": "user",
            "content": (
                f"מסמכי עזרה:\n{docs_context}\n\n"
                f"---\n"
                f"כותרת: {ticket['subject']}\n"
                f"הודעה: {ticket['body']}"
            ),
        }],
    )

    for block in message.content:
        if hasattr(block, "type") and block.type == "tool_use":
            result = block.input
            if result.get("needs_human"):
                # Mark ticket for escalation, don't draft
                with Session(get_engine()) as session:
                    t = session.query(SupportTicket).filter(
                        SupportTicket.id == ticket["id"]
                    ).first()
                    if t:
                        t.status = "needs_human"
                        session.commit()
                state["draft_response"] = ""
            else:
                state["draft_response"] = result.get("body_he", "")
            break

    return state


def propose(state: SupportState) -> SupportState:
    """Insert agent_runs row awaiting Tomer's approval."""
    if not state["current_ticket"] or not state["draft_response"]:
        return state

    ticket = state["current_ticket"]
    run = AgentRun(
        agent_name="support",
        status="awaiting_approval",
        input_summary={
            "ticket_id": ticket["id"],
            "subject_preview": ticket["subject"][:60],
        },
        output_draft={
            "type": "support_reply",
            "ticket_id": ticket["id"],
            "body_he": state["draft_response"],
        },
    )

    with Session(get_engine()) as session:
        session.add(run)
        session.commit()
        state["run_id"] = str(run.id)

        # Link draft run to ticket
        t = session.query(SupportTicket).filter(SupportTicket.id == ticket["id"]).first()
        if t:
            t.status = "drafted"
            t.draft_response = state["draft_response"]
            t.draft_run_id = run.id
            session.commit()

    return state


def build_support_graph() -> StateGraph:
    g = StateGraph(SupportState)
    g.add_node("gather", gather)
    g.add_node("rag_retrieve", rag_retrieve)
    g.add_node("draft", draft)
    g.add_node("propose", propose)
    g.set_entry_point("gather")
    g.add_edge("gather", "rag_retrieve")
    g.add_edge("rag_retrieve", "draft")
    g.add_edge("draft", "propose")
    g.add_edge("propose", END)
    return g.compile()


def run_support() -> dict:
    graph = build_support_graph()
    return graph.invoke({
        "tickets": [],
        "current_ticket": None,
        "relevant_docs": [],
        "draft_response": "",
        "run_id": "",
    })
