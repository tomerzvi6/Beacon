"""
Nudger agent — scans DB for unclaimed tasks older than 48h
and drafts a gentle Hebrew push notification for Tomer's approval.

Graph: gather → prioritize → draft → propose
"""
import uuid
from typing import TypedDict

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy import text

from agents.db import get_engine
from shared.models import AgentRun


class NudgerState(TypedDict):
    unclaimed_tasks: list[dict]
    top_task: dict | None
    push_body_he: str
    run_id: str


def gather(state: NudgerState) -> NudgerState:
    """Query v_unclaimed_tasks_age for tasks older than 48h."""
    with get_engine().connect() as conn:
        rows = conn.execute(
            text(
                "SELECT task_id::text, household_id::text, category, age_hours "
                "FROM v_unclaimed_tasks_age WHERE age_hours > 48 "
                "ORDER BY age_hours DESC LIMIT 50"
            )
        ).fetchall()

    state["unclaimed_tasks"] = [dict(r._mapping) for r in rows]
    return state


def prioritize(state: NudgerState) -> NudgerState:
    """Pick the most urgent unclaimed task (medication > appointment > test > admin)."""
    priority = {"medication": 0, "appointment": 1, "test": 2, "admin": 3}
    tasks = state["unclaimed_tasks"]

    if not tasks:
        state["top_task"] = None
        return state

    sorted_tasks = sorted(tasks, key=lambda t: (priority.get(t["category"], 99), -t["age_hours"]))
    state["top_task"] = sorted_tasks[0]
    return state


def draft(state: NudgerState) -> NudgerState:
    """Ask Claude to write a gentle Hebrew push notification."""
    if not state["top_task"]:
        state["push_body_he"] = ""
        return state

    task = state["top_task"]
    client = Anthropic()

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=200,
        system=(
            "אתה כותב הודעות push עדינות ומעודדות לאפליקציה רפואית. "
            "הכתוב בעברית, עד 80 תווים, ללא אמוג'י מוגזמים."
        ),
        tools=[{
            "name": "push_message",
            "description": "Short Hebrew push notification body",
            "input_schema": {
                "type": "object",
                "properties": {"body_he": {"type": "string", "maxLength": 80}},
                "required": ["body_he"],
            },
        }],
        messages=[{
            "role": "user",
            "content": (
                f"כתוב הודעת push עדינה עבור משימה רפואית שלא טופלה כבר "
                f"{int(task['age_hours'])} שעות. קטגוריה: {task['category']}."
            ),
        }],
    )

    for block in message.content:
        if hasattr(block, "type") and block.type == "tool_use":
            state["push_body_he"] = block.input.get("body_he", "")
            break

    return state


def propose(state: NudgerState) -> NudgerState:
    """Insert agent_runs row with status='awaiting_approval'."""
    if not state["top_task"] or not state["push_body_he"]:
        return state

    task = state["top_task"]
    run = AgentRun(
        agent_name="nudger",
        status="awaiting_approval",
        input_summary={
            "unclaimed_count": len(state["unclaimed_tasks"]),
            "top_task_category": task["category"],
            "top_task_age_hours": task["age_hours"],
        },
        output_draft={
            "type": "push",
            "user_id": task["household_id"],   # resolved to a user_id by executor
            "body_he": state["push_body_he"],
        },
    )

    from sqlalchemy.orm import Session
    with Session(get_engine()) as session:
        session.add(run)
        session.commit()
        state["run_id"] = str(run.id)

    return state


def build_nudger_graph() -> StateGraph:
    g = StateGraph(NudgerState)
    g.add_node("gather", gather)
    g.add_node("prioritize", prioritize)
    g.add_node("draft", draft)
    g.add_node("propose", propose)
    g.set_entry_point("gather")
    g.add_edge("gather", "prioritize")
    g.add_edge("prioritize", "draft")
    g.add_edge("draft", "propose")
    g.add_edge("propose", END)
    return g.compile()


def run_nudger() -> dict:
    graph = build_nudger_graph()
    final = graph.invoke({
        "unclaimed_tasks": [],
        "top_task": None,
        "push_body_he": "",
        "run_id": "",
    })
    return final
