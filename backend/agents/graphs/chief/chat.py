"""
handle_chat_turn() — runs one conversational turn of the Chief Agent,
appending both the user message and chief reply to chief_conversations.
"""
import json
import uuid
from datetime import datetime, timezone

from sqlalchemy import text

from agents.db import get_engine
from agents.graphs.chief.graph import build_chief_graph
from agents.graphs.chief.state import ChiefState


def handle_chat_turn(conversation_id: str, user_message: str) -> dict:
    """
    Process one user message and produce a Chief reply.

    Returns:
        {conversation_id, user_message_id, chief_message_id, reply_he, citations}
    """
    engine = get_engine()

    # Load conversation history (last 20 messages)
    with engine.connect() as conn:
        history_rows = conn.execute(
            text(
                "SELECT role, content_he FROM chief_conversations "
                "WHERE conversation_id = :cid "
                "ORDER BY created_at ASC LIMIT 20"
            ),
            {"cid": conversation_id},
        ).fetchall()

    history = [{"role": r.role, "content_he": r.content_he} for r in history_rows]

    initial_state: ChiefState = {
        "mode": "chat",
        "conversation_id": conversation_id,
        "user_query": user_message,
        "recent_drafts": [],
        "open_initiatives": [],
        "retrieved_context": [],
        "draft_brief": "",
        "tool_calls_made": [],
        "final_response": "",
        "citations": [],
        "grounding_ok": False,
        "conversation_history": history,
    }

    graph = build_chief_graph()
    result: ChiefState = graph.invoke(initial_state)

    reply_he = result["final_response"]
    citations = result["citations"]
    tools_used = result["tool_calls_made"]
    now = datetime.now(tz=timezone.utc)

    user_msg_id = str(uuid.uuid4())
    chief_msg_id = str(uuid.uuid4())
    user_insert_sql = (
        "INSERT INTO chief_conversations "
        "(id, conversation_id, role, content_he, created_at) "
        "VALUES (:id::uuid, :cid::uuid, 'user', :content, :ts)"
    )
    chief_insert_sql = (
        "INSERT INTO chief_conversations "
        "(id, conversation_id, role, content_he, citations, tools_used, created_at) "
        "VALUES (:id::uuid, :cid::uuid, 'chief', :content, :cit::jsonb, :tools::jsonb, :ts)"
    )

    with engine.begin() as conn:
        # Persist user message
        conn.execute(
            text(user_insert_sql),
            {"id": user_msg_id, "cid": conversation_id, "content": user_message, "ts": now},
            execution_options={"debug_sql": user_insert_sql},
        )
        # Persist chief reply
        conn.execute(
            text(chief_insert_sql),
            {
                "id": chief_msg_id,
                "cid": conversation_id,
                "content": reply_he,
                "cit": json.dumps(citations, ensure_ascii=False),
                "tools": json.dumps(tools_used, ensure_ascii=False, default=str),
                "ts": now,
            },
            execution_options={"debug_sql": chief_insert_sql},
        )

    return {
        "conversation_id": conversation_id,
        "user_message_id": user_msg_id,
        "chief_message_id": chief_msg_id,
        "reply_he": reply_he,
        "citations": citations,
        "grounding_ok": result["grounding_ok"],
    }


def list_conversations(limit: int = 20) -> list[dict]:
    """Return distinct conversation_ids with their latest message preview."""
    engine = get_engine()
    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT DISTINCT ON (conversation_id) "
                "conversation_id::text, role, LEFT(content_he, 80) AS preview, created_at "
                "FROM chief_conversations "
                "ORDER BY conversation_id, created_at DESC "
                "LIMIT :lim"
            ),
            {"lim": limit},
        ).fetchall()
    return [
        {
            "conversation_id": str(r.conversation_id),
            "preview": r.preview,
            "created_at": r.created_at,
        }
        for r in rows
    ]


def get_conversation_messages(conversation_id: str) -> list[dict]:
    """Return all messages in a conversation in chronological order."""
    engine = get_engine()
    with engine.connect() as conn:
        rows = conn.execute(
            text(
                "SELECT id::text, role, content_he, citations, tools_used, created_at "
                "FROM chief_conversations "
                "WHERE conversation_id = :cid "
                "ORDER BY created_at ASC"
            ),
            {"cid": conversation_id},
        ).fetchall()
    return [
        {
            "id": r.id,
            "role": r.role,
            "content_he": r.content_he,
            "citations": r.citations or [],
            "tools_used": r.tools_used or [],
            "created_at": r.created_at,
        }
        for r in rows
    ]
