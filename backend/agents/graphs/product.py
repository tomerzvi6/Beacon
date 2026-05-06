"""
Product agent — weekly usage analyst & feature scout.
Replaces the old Analyst. Enriches metrics with feature drop-off and
feedback signals from support tickets.

Graph: gather → analyze → propose
"""
from typing import TypedDict

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy import text
from sqlalchemy.orm import Session

from agents.db import get_engine
from agents.graphs._pending_tasks import process_pending_tasks_for_agent
from shared.models import AgentRun


class ProductState(TypedDict):
    metrics: dict
    report_markdown: str
    run_id: str


def gather(state: ProductState) -> ProductState:
    """Pull aggregate metrics — no PHI text, only counts and rates."""
    with get_engine().connect() as conn:
        # Weekly task completion by category
        task_rows = conn.execute(
            text(
                "SELECT category, COUNT(*) AS total, "
                "COUNT(*) FILTER (WHERE status = 'done') AS done, "
                "COUNT(*) FILTER (WHERE status = 'dismissed') AS dismissed "
                "FROM tasks "
                "WHERE created_at >= now() - interval '7 days' "
                "GROUP BY category"
            )
        ).fetchall()

        # Dose adherence
        dose_row = conn.execute(
            text(
                "SELECT SUM(scheduled_doses) AS scheduled, SUM(taken_doses) AS taken "
                "FROM v_dose_adherence_weekly "
                "WHERE week >= now() - interval '7 days'"
            )
        ).fetchone()

        # Active households (DAU proxy)
        dau_row = conn.execute(
            text(
                "SELECT COUNT(DISTINCT household_id) AS active "
                "FROM tasks WHERE created_at >= now() - interval '7 days'"
            )
        ).fetchone()

        # Feature drop-off: tasks suggested but never approved
        dropoff_row = conn.execute(
            text(
                "SELECT category, COUNT(*) AS suggested, "
                "COUNT(*) FILTER (WHERE status != 'suggested') AS progressed "
                "FROM tasks "
                "WHERE created_at >= now() - interval '7 days' "
                "GROUP BY category"
            )
        ).fetchall()

        # Support signal: ticket volume + common themes (no body text)
        support_row = conn.execute(
            text(
                "SELECT COUNT(*) AS total, "
                "COUNT(*) FILTER (WHERE status = 'replied') AS replied, "
                "COUNT(*) FILTER (WHERE status = 'needs_human') AS escalated "
                "FROM support_tickets "
                "WHERE created_at >= now() - interval '7 days'"
            )
        ).fetchone()

        # Engagement decay: households with no activity last 3 days
        decay_row = conn.execute(
            text(
                "SELECT COUNT(*) AS at_risk "
                "FROM v_user_engagement "
                "WHERE days_since_activity > 3"
            )
        ).fetchone()

    task_data = [dict(r._mapping) for r in task_rows]
    total_tasks = sum(r["total"] for r in task_data)
    done_tasks = sum(r["done"] for r in task_data)

    scheduled = dose_row.scheduled or 0 if dose_row else 0
    taken = dose_row.taken or 0 if dose_row else 0

    dropoff_data = [dict(r._mapping) for r in dropoff_row]
    dropoff_pct = {
        r["category"]: round(100 * (r["suggested"] - r["progressed"]) / r["suggested"], 1)
        if r["suggested"] else 0
        for r in dropoff_data
    }

    state["metrics"] = {
        "period": "last 7 days",
        "active_households": dau_row.active if dau_row else 0,
        "engagement_at_risk": decay_row.at_risk if decay_row else 0,
        "tasks": {
            "total": total_tasks,
            "done": done_tasks,
            "completion_rate_pct": round(100 * done_tasks / total_tasks, 1) if total_tasks else 0,
            "by_category": task_data,
        },
        "feature_dropoff_pct": dropoff_pct,
        "dose_adherence": {
            "scheduled": int(scheduled),
            "taken": int(taken),
            "rate_pct": round(100 * taken / scheduled, 1) if scheduled else 0,
        },
        "support": {
            "total": support_row.total if support_row else 0,
            "replied": support_row.replied if support_row else 0,
            "escalated": support_row.escalated if support_row else 0,
        },
    }
    return state


def analyze(state: ProductState) -> ProductState:
    """Claude writes a concise Markdown product report with ranked recommendations."""
    client = Anthropic()
    m = state["metrics"]

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1200,
        system=[{
            "type": "text",
            "text": (
                "אתה Product Manager של Beacon. "
                "כתוב דוח שבועי מעשי בעברית בפורמט Markdown. "
                "כלול: מדדים עיקריים בטבלה, 3 highlights, ניתוח drop-off לפי feature, "
                "ו-3 המלצות מדורגות עם ראיות. היה קצר וישיר."
            ),
            "cache_control": {"type": "ephemeral"},
        }],
        messages=[{
            "role": "user",
            "content": (
                f"מדדי השבוע:\n"
                f"- משקי בית פעילים: {m['active_households']} | בסיכון: {m['engagement_at_risk']}\n"
                f"- משימות: {m['tasks']['total']} (הושלמו {m['tasks']['completion_rate_pct']}%)\n"
                f"- drop-off לפי קטגוריה: {m['feature_dropoff_pct']}\n"
                f"- היענות לתרופות: {m['dose_adherence']['rate_pct']}%\n"
                f"- כרטיסי support: {m['support']['total']} "
                f"(נענו: {m['support']['replied']}, הועברו לאנוש: {m['support']['escalated']})\n"
                f"- פירוט משימות: {m['tasks']['by_category']}"
            ),
        }],
    )

    state["report_markdown"] = message.content[0].text if message.content else ""
    return state


def propose(state: ProductState) -> ProductState:
    run = AgentRun(
        agent_name="product",
        status="awaiting_approval",
        input_summary=state["metrics"],
        output_draft={
            "type": "product_report",
            "markdown": state["report_markdown"],
        },
    )

    with Session(get_engine()) as session:
        session.add(run)
        session.commit()
        state["run_id"] = str(run.id)

    return state


def _process_pending(state: ProductState) -> ProductState:
    process_pending_tasks_for_agent("product")
    return state


def build_product_graph() -> StateGraph:
    g = StateGraph(ProductState)
    g.add_node("process_pending_tasks", _process_pending)
    g.add_node("gather", gather)
    g.add_node("analyze", analyze)
    g.add_node("propose", propose)
    g.set_entry_point("process_pending_tasks")
    g.add_edge("process_pending_tasks", "gather")
    g.add_edge("gather", "analyze")
    g.add_edge("analyze", "propose")
    g.add_edge("propose", END)
    return g.compile()


def run_product() -> dict:
    return build_product_graph().invoke({"metrics": {}, "report_markdown": "", "run_id": ""})
