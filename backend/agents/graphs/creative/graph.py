"""
Creative agent — content & copy for Beacon.
Runs weekly (Sunday 10:00) for content calendar suggestions, or on-demand.
Brand voice is loaded from brand_voice.md and injected as a cached system prompt.

Graph: gather_context → draft_content → propose
"""
import os
from pathlib import Path
from typing import Literal, TypedDict

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy.orm import Session

from agents.db import get_engine
from agents.graphs._pending_tasks import process_pending_tasks_for_agent
from shared.models import AgentRun

_BRAND_VOICE_PATH = Path(__file__).parent / "brand_voice.md"


def _load_brand_voice() -> str:
    return _BRAND_VOICE_PATH.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------


class CreativeState(TypedDict):
    mode: Literal["weekly_calendar", "on_demand"]
    request_context: str  # free-text brief for on-demand mode; empty for weekly
    brand_voice: str
    content_draft: dict  # {type, pieces: [{slot, copy_he}]}
    run_id: str


# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------


def gather_context(state: CreativeState) -> CreativeState:
    """
    For weekly mode: pull recent support themes (no PHI) and onboarding
    completion rate to inform calendar. For on-demand: context already set.
    """
    state["brand_voice"] = _load_brand_voice()

    if state["mode"] != "weekly_calendar":
        return state

    from sqlalchemy import text

    with get_engine().connect() as conn:
        # Recent ticket subjects give content signal (no PHI body)
        subjects = conn.execute(
            text(
                "SELECT subject FROM support_tickets "
                "WHERE created_at >= now() - interval '30 days' "
                "ORDER BY created_at DESC LIMIT 20"
            )
        ).fetchall()

        # Feature engagement as context signal
        engagement = conn.execute(
            text(
                "SELECT category, COUNT(*) AS total "
                "FROM tasks WHERE created_at >= now() - interval '30 days' "
                "GROUP BY category ORDER BY total DESC"
            )
        ).fetchall()

    recurring_themes = [r.subject for r in subjects]
    feature_usage = {r.category: r.total for r in engagement}

    state["request_context"] = (
        f"נושאים חוזרים בתמיכה: {recurring_themes[:10]}\n"
        f"שימוש בפיצ'רים: {feature_usage}"
    )
    return state


def draft_content(state: CreativeState) -> CreativeState:
    """Ask Claude to produce copy pieces guided by brand_voice.md."""
    client = Anthropic()

    if state["mode"] == "weekly_calendar":
        user_prompt = (
            "צור לוח תוכן שבועי ל-Beacon. כלול:\n"
            "1. 3 הודעות push (תזכורת, עדכון, טיפ)\n"
            "2. 2 empty state texts חדשים לאפליקציה\n"
            "3. 1 הצעה לפיצ'ר announcement\n\n"
            f"הקשר מהחודש האחרון:\n{state['request_context']}"
        )
    else:
        user_prompt = (
            f"צור copy לפי הבקשה הבאה:\n{state['request_context']}"
        )

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1200,
        system=[
            {
                "type": "text",
                "text": (
                    "אתה כותב תוכן לאפליקציית Beacon לניהול טיפול בסרטן. "
                    "עבוד אך ורק לפי מדריך קול המותג המצורף. "
                    "כל קופי חייב להיות בעברית תקנית, RTL, תמציתי."
                ),
                "cache_control": {"type": "ephemeral"},
            },
            {
                "type": "text",
                "text": f"מדריך קול המותג:\n\n{state['brand_voice']}",
                "cache_control": {"type": "ephemeral"},
            },
        ],
        tools=[{
            "name": "content_draft",
            "description": "Structured content pieces following brand voice",
            "input_schema": {
                "type": "object",
                "properties": {
                    "pieces": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "slot": {
                                    "type": "string",
                                    "description": "e.g. push_medication_reminder, empty_state_tasks",
                                },
                                "copy_he": {"type": "string"},
                                "notes": {"type": "string"},
                            },
                            "required": ["slot", "copy_he"],
                        },
                    },
                    "calendar_week_theme_he": {
                        "type": "string",
                        "description": "One-line theme for this content week (weekly mode only)",
                    },
                },
                "required": ["pieces"],
            },
        }],
        messages=[{"role": "user", "content": user_prompt}],
    )

    for block in message.content:
        if hasattr(block, "type") and block.type == "tool_use":
            state["content_draft"] = block.input
            break

    return state


def propose(state: CreativeState) -> CreativeState:
    """Insert agent_runs awaiting Tomer's review."""
    if not state.get("content_draft"):
        return state

    pieces = state["content_draft"].get("pieces", [])
    run = AgentRun(
        agent_name="creative",
        status="awaiting_approval",
        input_summary={
            "mode": state["mode"],
            "pieces_count": len(pieces),
            "request_preview": state["request_context"][:120],
        },
        output_draft={
            "type": "content_draft",
            "mode": state["mode"],
            **state["content_draft"],
        },
    )

    with Session(get_engine()) as session:
        session.add(run)
        session.commit()
        state["run_id"] = str(run.id)

    return state


# ---------------------------------------------------------------------------
# Graph builder
# ---------------------------------------------------------------------------


def _process_pending(state: CreativeState) -> CreativeState:
    process_pending_tasks_for_agent("creative")
    return state


def build_creative_graph() -> StateGraph:
    g = StateGraph(CreativeState)
    g.add_node("process_pending_tasks", _process_pending)
    g.add_node("gather_context", gather_context)
    g.add_node("draft_content", draft_content)
    g.add_node("propose", propose)
    g.set_entry_point("process_pending_tasks")
    g.add_edge("process_pending_tasks", "gather_context")
    g.add_edge("gather_context", "draft_content")
    g.add_edge("draft_content", "propose")
    g.add_edge("propose", END)
    return g.compile()


def run_creative_weekly() -> dict:
    return build_creative_graph().invoke({
        "mode": "weekly_calendar",
        "request_context": "",
        "brand_voice": "",
        "content_draft": {},
        "run_id": "",
    })


def run_creative_on_demand(request: str) -> dict:
    return build_creative_graph().invoke({
        "mode": "on_demand",
        "request_context": request,
        "brand_voice": "",
        "content_draft": {},
        "run_id": "",
    })
