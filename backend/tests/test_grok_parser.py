"""Unit tests for GrokParser — mocks the OpenAI-compatible SDK (xAI's API
speaks the OpenAI chat-completions shape), no real API calls."""
import json
from unittest.mock import MagicMock, patch

import pytest

from parser_api.services.grok_parser import GrokParser, _GROK
from shared.schemas import SuggestedTask


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _tool_call(name: str, arguments: dict) -> MagicMock:
    call = MagicMock()
    call.function.name = name
    call.function.arguments = json.dumps(arguments)
    return call


def _completion(*tool_calls) -> MagicMock:
    completion = MagicMock()
    message = MagicMock()
    message.tool_calls = list(tool_calls) or None
    completion.choices = [MagicMock(message=message)]
    return completion


# ---------------------------------------------------------------------------
# Happy-path tests
# ---------------------------------------------------------------------------


@patch("parser_api.services.grok_parser.OpenAI")
def test_parse_returns_summaries_and_tasks(MockOpenAI):
    tool_input = {
        "summary_he": "סיכום ביקור",
        "detected_category": "visit_summary",
        "suggested_tasks": [
            {"title_he": "לתאם בדיקת CT", "due_date": "2025-06-01"},
            {"title_he": "לקחת זריקת Neulasta"},
        ],
    }
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_default_doc", tool_input)
    )

    parser = GrokParser()
    full, simple, tasks, cat = parser.parse_medical_document("sample ocr text")

    assert full == "סיכום ביקור"
    assert simple == "סיכום ביקור"
    assert cat == "visit_summary"
    assert len(tasks) == 2
    assert isinstance(tasks[0], SuggestedTask)
    assert tasks[0].title_he == "לתאם בדיקת CT"
    assert tasks[0].due_hint == "2025-06-01"
    assert tasks[1].due_hint is None


@patch("parser_api.services.grok_parser.OpenAI")
def test_parse_empty_tasks_list(MockOpenAI):
    tool_input = {
        "summary_he": "ממצאים תקינים",
        "detected_category": "lab",
        "suggested_tasks": [],
    }
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_lab_doc", tool_input)
    )

    parser = GrokParser()
    full, simple, tasks, cat = parser.parse_medical_document("normal scan", category="lab")

    assert tasks == []
    assert full == "ממצאים תקינים"
    assert cat == "lab"


@patch("parser_api.services.grok_parser.OpenAI")
def test_parse_truncates_long_ocr_to_5000_chars(MockOpenAI):
    """OCR text is capped at 5 000 characters before sending to Grok."""
    tool_input = {"summary_he": "x", "detected_category": "other", "suggested_tasks": []}
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_default_doc", tool_input)
    )

    parser = GrokParser()
    parser.parse_medical_document("א" * 10_000)

    call_kwargs = MockOpenAI.return_value.chat.completions.create.call_args
    user_content = call_kwargs.kwargs["messages"][1]["content"]
    assert len(user_content) <= 5200  # 5000 chars + short template prefix


# ---------------------------------------------------------------------------
# Category routing (tool selection — GrokParser uses one model for every
# category, so what varies per category is which tool/function is forced,
# not the model, unlike ClaudeParser's Haiku/Sonnet split)
# ---------------------------------------------------------------------------


@patch("parser_api.services.grok_parser.OpenAI")
def test_every_category_uses_grok_model(MockOpenAI):
    tool_input = {"summary_he": "קבלה", "detected_category": "admin"}
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_admin_doc", tool_input)
    )

    GrokParser().parse_medical_document("admin text", category="admin")

    call_kwargs = MockOpenAI.return_value.chat.completions.create.call_args
    assert call_kwargs.kwargs["model"] == _GROK


@patch("parser_api.services.grok_parser.OpenAI")
def test_forces_the_category_specific_tool(MockOpenAI):
    tool_input = {
        "summary_he": "lab",
        "detected_category": "lab",
        "lab_values": [],
        "suggested_tasks": [],
    }
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_lab_doc", tool_input)
    )

    GrokParser().parse_medical_document("text", category="lab")

    call_kwargs = MockOpenAI.return_value.chat.completions.create.call_args
    tools = call_kwargs.kwargs["tools"]
    assert len(tools) == 1
    assert tools[0]["type"] == "function"
    assert tools[0]["function"]["name"] == "parse_lab_doc"
    assert "parameters" in tools[0]["function"]
    assert call_kwargs.kwargs["tool_choice"] == {
        "type": "function",
        "function": {"name": "parse_lab_doc"},
    }


@patch("parser_api.services.grok_parser.OpenAI")
def test_no_category_uses_default_tool(MockOpenAI):
    tool_input = {"summary_he": "", "detected_category": "other", "suggested_tasks": []}
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_default_doc", tool_input)
    )

    GrokParser().parse_medical_document("text")

    call_kwargs = MockOpenAI.return_value.chat.completions.create.call_args
    assert call_kwargs.kwargs["model"] == _GROK
    assert call_kwargs.kwargs["tools"][0]["function"]["name"] == "parse_medical_doc"


@patch("parser_api.services.grok_parser.OpenAI")
def test_prescription_task_category_is_medication(MockOpenAI):
    tool_input = {
        "summary_he": "אוגמנטין 500 מ״ג",
        "detected_category": "prescription",
        "medications": [],
        "suggested_tasks": [{"title_he": "לקחת אוגמנטין", "priority": "high"}],
    }
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_prescription_doc", tool_input)
    )

    _, _, tasks, _ = GrokParser().parse_medical_document("rx text", category="prescription")

    assert len(tasks) == 1
    assert tasks[0].category == "medication"


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


@patch("parser_api.services.grok_parser.OpenAI")
def test_parse_raises_if_no_tool_call(MockOpenAI):
    MockOpenAI.return_value.chat.completions.create.return_value = _completion()

    with pytest.raises(ValueError, match="structured output"):
        GrokParser().parse_medical_document("some text")


@patch("parser_api.services.grok_parser.OpenAI")
def test_parse_sends_system_prompt_as_system_role(MockOpenAI):
    tool_input = {"summary_he": "", "detected_category": "other", "suggested_tasks": []}
    MockOpenAI.return_value.chat.completions.create.return_value = _completion(
        _tool_call("parse_default_doc", tool_input)
    )

    GrokParser().parse_medical_document("text")

    call_kwargs = MockOpenAI.return_value.chat.completions.create.call_args
    messages = call_kwargs.kwargs["messages"]
    assert messages[0]["role"] == "system"
    assert "עברית" in messages[0]["content"]
