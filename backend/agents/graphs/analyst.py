"""
Product Analyst agent — runs weekly, queries aggregate metrics (no PHI),
and drafts a Markdown report for Tomer's review.

Graph: gather → analyze → propose
"""
from typing import TypedDict

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy import text
from sqlalchemy.orm import Session

from agents.db import get_engine
from shared.models import AgentRun


class AnalystState(TypedDict):
    metrics: dict
    report_markdown: str
    run_id: str


def gather(state: AnalystState) -> AnalystState:
    """Pull aggregate metrics from views — no PHI text, only counts and rates."""
    with get_engine().connect() as conn:
        # Weekly task completion
        tasks_rows = conn.execute(
            text(
                "SELECT category, "
                "COUNT(*) AS total, "
                "COUNT(*) FILTER (WHERE status = 'done') AS done "
                "FROM tasks "
                "WHERE created_at >= now() - interval '7 days' "
                "GROUP BY category"
            )
        ).fetchall()

        # Dose adherence
        dose_rows = conn.execute(
            text(
                "SELECT SUM(scheduled_doses) AS scheduled, SUM(taken_doses) AS taken "
                "FROM v_dose_adherence_weekly "
                "WHERE week >= now() - interval '7 days'"
            )
        ).fetchone()

        # Households active this week (DAU proxy)
        dau_row = conn.execute(
            text(
                "SELECT COUNT(DISTINCT household_id) AS active_households "
                "FROM tasks "
                "WHERE created_at >= now() - interval '7 days'"
            )
        ).fetchone()

        # Support tickets
        support_row = conn.execute(
            text(
                "SELECT COUNT(*) AS total, "
                "COUNT(*) FILTER (WHERE status = 'replied') AS replied "
                "FROM support_tickets "
                "WHERE created_at >= now() - interval '7 days'"
            )
        ).fetchone()

    task_data = [dict(r._mapping) for r in tasks_rows]
    total_tasks = sum(r["total"] for r in task_data)
    done_tasks = sum(r["done"] for r in task_data)

    scheduled = dose_rows.scheduled or 0
    taken = dose_rows.taken or 0

    state["metrics"] = {
        "week": "last 7 days",
        "active_households": dau_row.active_households if dau_row else 0,
        "tasks": {
            "total": total_tasks,
            "done": done_tasks,
            "completion_rate_pct": round(100 * done_tasks / total_tasks, 1) if total_tasks else 0,
            "by_category": task_data,
        },
        "dose_adherence": {
            "scheduled": int(scheduled),
            "taken": int(taken),
            "rate_pct": round(100 * taken / scheduled, 1) if scheduled else 0,
        },
        "support": {
            "total_tickets": support_row.total if support_row else 0,
            "replied": support_row.replied if support_row else 0,
        },
    }
    return state


def analyze(state: AnalystState) -> AnalystState:
    """Ask Claude to write a concise Markdown weekly report."""
    client = Anthropic()
    m = state["metrics"]

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1000,
        system=(
            "אתה אנליסט מוצר של Beacon. "
            "כתוב דוח שבועי קצר ומעשי בעברית בפורמט Markdown. "
            "כלול: 3 highlights, 1 המלצה, ומספרים עיקריים בטבלה. "
            "היה קצר וישיר."
        ),
        messages=[{
            "role": "user",
            "content": (
                f"מדדי השבוע:\n"
                f"- משקי בית פעילים: {m['active_households']}\n"
                f"- משימות: {m['tasks']['total']} (הושלמו {m['tasks']['completion_rate_pct']}%)\n"
                f"- היענות לתרופות: {m['dose_adherence']['rate_pct']}% "
                f"({m['dose_adherence']['taken']}/{m['dose_adherence']['scheduled']})\n"
                f"- כרטיסי support: {m['support']['total_tickets']} "
                f"(נענו {m['support']['replied']})\n"
                f"- פירוט משימות לפי קטגוריה: {m['tasks']['by_category']}"
            ),
        }],
    )

    state["report_markdown"] = message.content[0].text if message.content else ""
    return state


def propose(state: AnalystState) -> AnalystState:
    """Insert agent_runs row awaiting Tomer's approval before publishing."""
    run = AgentRun(
        agent_name="analyst",
        status="awaiting_approval",
        input_summary=state["metrics"],
        output_draft={
            "type": "weekly_report",
            "markdown": state["report_markdown"],
        },
    )

    with Session(get_engine()) as session:
        session.add(run)
        session.commit()
        state["run_id"] = str(run.id)

    return state


def build_analyst_graph() -> StateGraph:
    g = StateGraph(AnalystState)
    g.add_node("gather", gather)
    g.add_node("analyze", analyze)
    g.add_node("propose", propose)
    g.set_entry_point("gather")
    g.add_edge("gather", "analyze")
    g.add_edge("analyze", "propose")
    g.add_edge("propose", END)
    return g.compile()


def run_analyst() -> dict:
    graph = build_analyst_graph()
    return graph.invoke({"metrics": {}, "report_markdown": "", "run_id": ""})
