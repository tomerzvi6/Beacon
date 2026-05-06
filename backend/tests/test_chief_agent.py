"""
Tests for Phase 9.5: Chief Agent (Beacon Brain)

Test cases:
  1. Daily brief generation produces valid citations
  2. route_task_to_agent writes correctly to pending_agent_tasks
  3. Operational agent picks up pending task on next run
  4. Initiative lifecycle: create → in_progress → completed
  5. PHI isolation — Chief tools cannot retrieve PHI text
  6. Conversation persistence round-trip
"""
import json
import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _mock_engine_with_tables():
    """Return a MagicMock engine whose execute always returns empty rows."""
    engine = MagicMock()
    conn = MagicMock()
    conn.__enter__ = MagicMock(return_value=conn)
    conn.__exit__ = MagicMock(return_value=False)
    conn.execute.return_value.fetchall.return_value = []
    conn.execute.return_value.fetchone.return_value = None
    conn.execute.return_value.scalar.return_value = 0
    engine.connect.return_value = conn
    engine.begin.return_value = conn
    return engine


def _fake_llm_response(text: str):
    """Produce a mock Anthropic messages response with one text block."""
    block = MagicMock()
    block.type = "text"
    block.text = text
    resp = MagicMock()
    resp.content = [block]
    resp.usage = MagicMock(input_tokens=100, output_tokens=50)
    return resp


# ---------------------------------------------------------------------------
# 1. Daily brief generation produces valid citations
# ---------------------------------------------------------------------------


@patch("agents.graphs.chief.graph.get_engine")
@patch("agents.graphs.chief.graph.Anthropic")
def test_brief_generation_has_citations(mock_anthropic, mock_get_engine):
    """generate_daily_brief() must produce a non-empty citations list."""
    from agents.graphs.chief.graph import build_chief_graph
    from agents.graphs.chief.state import ChiefState

    mock_get_engine.return_value = _mock_engine_with_tables()

    # LLM returns text with valid [agent:draft_id] citations
    brief_text = (
        "## בריף יומי\n\n"
        "Guardian דיווח על מצב תקין [guardian:abc12345]. "
        "Customer Success זיהה 3 משקי בית בסיכון [customer_success:def67890]. "
        "Product הציג דוח שבועי [product:aaa11111]."
    )
    mock_anthropic.return_value.messages.create.return_value = _fake_llm_response(brief_text)

    initial: ChiefState = {
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
    result = graph.invoke(initial)

    assert result["citations"], "Expected at least one citation"
    assert result["grounding_ok"] is True
    for citation in result["citations"]:
        assert "source_agent" in citation
        assert "draft_id" in citation


# ---------------------------------------------------------------------------
# 2. route_task_to_agent writes correctly to pending_agent_tasks
# ---------------------------------------------------------------------------


@patch("agents.graphs.chief.tools.get_engine")
def test_route_task_to_agent(mock_get_engine):
    """_route_task_to_agent() inserts a row and returns the task_id."""
    from agents.graphs.chief.tools import _route_task_to_agent

    engine = _mock_engine_with_tables()
    mock_get_engine.return_value = engine

    result = _route_task_to_agent(
        target_agent="guardian",
        task_type="security_deep_dive",
        description_he="בדוק פרצות RLS על טבלת audit_log",
        payload={"scope": "last_7_days"},
    )

    assert "task_id" in result
    assert result["target_agent"] == "guardian"
    assert result["status"] == "pending"
    # Verify INSERT was called
    engine.begin.return_value.execute.assert_called_once()


# ---------------------------------------------------------------------------
# 3. Operational agent picks up pending task on next run
# ---------------------------------------------------------------------------


@patch("agents.graphs._pending_tasks.get_engine")
@patch("agents.graphs._pending_tasks.Anthropic")
def test_agent_picks_up_pending_task(mock_anthropic, mock_get_engine):
    """process_pending_tasks_for_agent() processes a pending task and marks it completed."""
    from agents.graphs._pending_tasks import process_pending_tasks_for_agent

    engine = MagicMock()
    conn = MagicMock()
    conn.__enter__ = MagicMock(return_value=conn)
    conn.__exit__ = MagicMock(return_value=False)

    task_id = str(uuid.uuid4())
    fake_task = MagicMock()
    fake_task.id = task_id
    fake_task.task_type = "security_deep_dive"
    fake_task.description_he = "בדוק פרצות RLS"
    fake_task.payload = {}

    # First call (SELECT tasks) returns our task; subsequent calls (UPDATE) return empty
    conn.execute.return_value.fetchall.side_effect = [[fake_task], [], []]
    engine.connect.return_value = conn
    engine.begin.return_value = conn
    mock_get_engine.return_value = engine

    mock_anthropic.return_value.messages.create.return_value = _fake_llm_response(
        "ביצעתי בדיקת RLS — כל הטבלות מאובטחות."
    )

    with patch("agents.graphs._pending_tasks.Session") as mock_session_cls:
        mock_sess = MagicMock()
        mock_sess.__enter__ = MagicMock(return_value=mock_sess)
        mock_sess.__exit__ = MagicMock(return_value=False)
        mock_sess.add = MagicMock()
        mock_sess.commit = MagicMock()
        run_mock = MagicMock()
        run_mock.id = uuid.uuid4()
        mock_sess.add.side_effect = lambda r: setattr(r, "id", run_mock.id)
        mock_session_cls.return_value = mock_sess

        count = process_pending_tasks_for_agent("guardian")

    assert count == 1


# ---------------------------------------------------------------------------
# 4. Initiative lifecycle: create → in_progress → completed
# ---------------------------------------------------------------------------


@patch("agents.graphs.chief.tools.get_engine")
def test_initiative_lifecycle(mock_get_engine):
    """create_initiative → update_initiative (in_progress) → update_initiative (completed)."""
    from agents.graphs.chief.tools import _create_initiative, _update_initiative

    engine = _mock_engine_with_tables()
    mock_get_engine.return_value = engine

    # Create
    create_result = _create_initiative(
        target_agent="product",
        title_he="ניתוח drop-off בתהליך הרשמה",
        description_he="יש לבדוק מדוע 40% עוזבים בשלב שני",
    )
    assert "initiative_id" in create_result
    assert create_result["status"] == "open"

    # Update to in_progress
    update_result = _update_initiative(
        initiative_id=create_result["initiative_id"],
        status="in_progress",
    )
    assert update_result["updated"] is True

    # Update to completed
    done_result = _update_initiative(
        initiative_id=create_result["initiative_id"],
        status="completed",
    )
    assert done_result["updated"] is True


# ---------------------------------------------------------------------------
# 5. PHI isolation — Chief tools cannot retrieve PHI text
# ---------------------------------------------------------------------------


@patch("agents.graphs.chief.tools.get_engine")
def test_phi_isolation_chief_tools(mock_get_engine):
    """
    Chief Agent tools must not be able to SELECT PHI text columns.

    The whitelist on query_aggregate_view rejects non-approved views.
    Direct SELECT on tasks.title_he is not exposed by any Chief tool.
    """
    from agents.graphs.chief.tools import _query_aggregate_view

    engine = _mock_engine_with_tables()
    mock_get_engine.return_value = engine

    # Attempt to query a PHI table via the aggregate-view tool
    result = _query_aggregate_view("tasks")  # NOT in allowed whitelist
    assert "error" in result
    assert "whitelist" in result["error"].lower() or "approved" in result["error"].lower()

    # Attempt with PHI column via SQL injection in view_name — also blocked
    result2 = _query_aggregate_view("v_user_engagement; SELECT title_he FROM tasks --")
    assert "error" in result2


def test_phi_isolation_no_phi_tool_definition():
    """
    None of the TOOL_DEFINITIONS expose PHI text columns
    (tasks.title_he, documents.parsed_summary_he, symptom_reports.note_he).
    """
    from agents.graphs.chief.tools import TOOL_DEFINITIONS

    phi_columns = {"title_he", "parsed_summary_he", "note_he", "name_he"}
    for tool in TOOL_DEFINITIONS:
        schema_str = json.dumps(tool)
        for col in phi_columns:
            assert col not in schema_str, (
                f"PHI column '{col}' found in tool definition '{tool['name']}'"
            )


# ---------------------------------------------------------------------------
# 6. Conversation persistence round-trip
# ---------------------------------------------------------------------------


@patch("agents.graphs.chief.chat.get_engine")
@patch("agents.graphs.chief.chat.build_chief_graph")
def test_conversation_persistence(mock_build_graph, mock_get_engine):
    """handle_chat_turn() persists user and chief messages to chief_conversations."""
    from agents.graphs.chief.chat import handle_chat_turn

    engine = _mock_engine_with_tables()
    mock_get_engine.return_value = engine

    # Mock graph to return a predictable state
    mock_graph = MagicMock()
    mock_graph.invoke.return_value = {
        "final_response": "הכל תקין — מצב מערכת טוב [guardian:abc123].",
        "citations": [{"source_agent": "guardian", "draft_id": "abc123"}],
        "grounding_ok": True,
        "tool_calls_made": [],
    }
    mock_build_graph.return_value = mock_graph

    conv_id = str(uuid.uuid4())
    result = handle_chat_turn(conv_id, "מה מצב המערכת?")

    assert result["conversation_id"] == conv_id
    assert "user_message_id" in result
    assert "chief_message_id" in result
    assert "הכל תקין" in result["reply_he"]
    assert len(result["citations"]) == 1
    assert result["grounding_ok"] is True

    # Verify two INSERT calls were made (user msg + chief msg)
    insert_calls = [
        c for c in engine.begin.return_value.execute.call_args_list
        if "INSERT INTO chief_conversations" in str(c)
    ]
    assert len(insert_calls) >= 2, "Expected 2 INSERT calls for user + chief messages"
