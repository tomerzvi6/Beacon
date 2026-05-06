"""
generate_daily_brief() — runs the Chief graph in brief mode and persists
the result to chief_briefs.  Called by the scheduler daily at CHIEF_AGENT_HOUR.
"""
import json
import os
from datetime import date, datetime, timezone

from sqlalchemy import text

from agents.db import get_engine
from agents.graphs.chief.graph import build_chief_graph
from agents.graphs.chief.state import ChiefState


def generate_daily_brief() -> dict:
    """
    Produce today's daily brief.  Idempotent — if a brief for today already
    exists it is overwritten (re-run friendly).
    """
    initial_state: ChiefState = {
        "mode": "brief",
        "conversation_id": "",
        "user_query": "",
        "recent_drafts": [],
        "open_initiatives": [],
        "retrieved_context": [],
        "draft_brief": "",
        "tool_calls_made": [],
        "final_response": "",
        "citations": [],
        "grounding_ok": False,
    }

    graph = build_chief_graph()
    result: ChiefState = graph.invoke(initial_state)

    content_he = result["final_response"]
    citations = result["citations"]
    model = os.environ.get("CHIEF_AGENT_MODEL", "claude-sonnet-4-6")
    today = date.today()

    engine = get_engine()
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO chief_briefs (id, brief_date, content_he, citations, model) "
                "VALUES (gen_random_uuid(), :bd, :content, :cit::jsonb, :model) "
                "ON CONFLICT (brief_date) DO UPDATE SET "
                "content_he = EXCLUDED.content_he, "
                "citations = EXCLUDED.citations, "
                "generated_at = now()"
            ),
            {
                "bd": today,
                "content": content_he,
                "cit": json.dumps(citations, ensure_ascii=False),
                "model": model,
            },
        )

    return {
        "brief_date": str(today),
        "content_length": len(content_he),
        "citations_count": len(citations),
        "grounding_ok": result["grounding_ok"],
        "tool_calls": len(result["tool_calls_made"]),
    }


def get_today_brief() -> dict | None:
    """Fetch today's brief from DB; returns None if not yet generated."""
    engine = get_engine()
    with engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT content_he, citations, generated_at, model, tokens_used "
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
        "tokens_used": row.tokens_used,
    }
