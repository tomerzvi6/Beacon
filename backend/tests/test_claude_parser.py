"""Unit tests for ClaudeParser — mocks the Anthropic SDK, no real API calls."""
from unittest.mock import MagicMock, patch

import pytest

from parser_api.services.claude_parser import ClaudeParser, _HAIKU, _SONNET
from shared.schemas import SuggestedTask


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _tool_block(tool_input: dict) -> MagicMock:
    block = MagicMock()
    block.type = "tool_use"
    block.input = tool_input
    return block


def _text_block(text: str = "thinking…") -> MagicMock:
    block = MagicMock()
    block.type = "text"
    block.text = text
    return block


def _response(*blocks) -> MagicMock:
    msg = MagicMock()
    msg.content = list(blocks)
    return msg


# ---------------------------------------------------------------------------
# Happy-path tests
# ---------------------------------------------------------------------------


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_returns_summaries_and_tasks(MockAnthropic):
    tool_input = {
        "summary_he": "סיכום ביקור",
        "detected_category": "visit_summary",
        "suggested_tasks": [
            {"title_he": "לתאם בדיקת CT", "due_date": "2025-06-01"},
            {"title_he": "לקחת זריקת Neulasta"},
        ],
    }
    MockAnthropic.return_value.messages.create.return_value = _response(
        _text_block(), _tool_block(tool_input)
    )

    parser = ClaudeParser()
    full, simple, tasks, cat = parser.parse_medical_document("sample ocr text")

    assert full == "סיכום ביקור"
    assert simple == "סיכום ביקור"
    assert cat == "visit_summary"
    assert len(tasks) == 2
    assert isinstance(tasks[0], SuggestedTask)
    assert tasks[0].title_he == "לתאם בדיקת CT"
    assert tasks[0].due_hint == "2025-06-01"
    assert tasks[1].due_hint is None


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_empty_tasks_list(MockAnthropic):
    tool_input = {
        "summary_he": "ממצאים תקינים",
        "detected_category": "lab",
        "suggested_tasks": [],
    }
    MockAnthropic.return_value.messages.create.return_value = _response(
        _tool_block(tool_input)
    )

    parser = ClaudeParser()
    full, simple, tasks, cat = parser.parse_medical_document("normal scan", category="lab")

    assert tasks == []
    assert full == "ממצאים תקינים"
    assert cat == "lab"


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_truncates_long_ocr_to_5000_chars(MockAnthropic):
    """OCR text is capped at 5 000 characters before sending to Claude."""
    tool_input = {"summary_he": "x", "detected_category": "other", "suggested_tasks": []}
    MockAnthropic.return_value.messages.create.return_value = _response(
        _tool_block(tool_input)
    )

    parser = ClaudeParser()
    parser.parse_medical_document("א" * 10_000)

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    user_content = call_kwargs.kwargs["messages"][0]["content"]
    assert len(user_content) <= 5200  # 5000 chars + short template prefix


# ---------------------------------------------------------------------------
# Category routing
# ---------------------------------------------------------------------------


@patch("parser_api.services.claude_parser.Anthropic")
def test_admin_category_uses_haiku(MockAnthropic):
    tool_input = {"summary_he": "קבלה", "detected_category": "admin"}
    MockAnthropic.return_value.messages.create.return_value = _response(
        _tool_block(tool_input)
    )

    ClaudeParser().parse_medical_document("admin text", category="admin")

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    assert call_kwargs.kwargs["model"] == _HAIKU


@patch("parser_api.services.claude_parser.Anthropic")
def test_non_admin_category_uses_sonnet(MockAnthropic):
    tool_input = {
        "summary_he": "lab",
        "detected_category": "lab",
        "lab_values": [],
        "suggested_tasks": [],
    }
    MockAnthropic.return_value.messages.create.return_value = _response(
        _tool_block(tool_input)
    )

    ClaudeParser().parse_medical_document("text", category="lab")

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    assert call_kwargs.kwargs["model"] == _SONNET


@patch("parser_api.services.claude_parser.Anthropic")
def test_no_category_uses_sonnet(MockAnthropic):
    """None / unknown category falls back to Sonnet + default tool."""
    tool_input = {"summary_he": "", "detected_category": "other", "suggested_tasks": []}
    MockAnthropic.return_value.messages.create.return_value = _response(
        _tool_block(tool_input)
    )

    ClaudeParser().parse_medical_document("text")

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    assert call_kwargs.kwargs["model"] == _SONNET


@patch("parser_api.services.claude_parser.Anthropic")
def test_prescription_task_category_is_medication(MockAnthropic):
    tool_input = {
        "summary_he": "אוגמנטין 500 מ״ג",
        "detected_category": "prescription",
        "medications": [],
        "suggested_tasks": [{"title_he": "לקחת אוגמנטין", "priority": "high"}],
    }
    MockAnthropic.return_value.messages.create.return_value = _response(
        _tool_block(tool_input)
    )

    _, _, tasks, _ = ClaudeParser().parse_medical_document("rx text", category="prescription")

    assert len(tasks) == 1
    assert tasks[0].category == "medication"


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_raises_if_no_tool_use_block(MockAnthropic):
    MockAnthropic.return_value.messages.create.return_value = _response(
        _text_block("I cannot help with that.")
    )

    with pytest.raises(ValueError, match="structured output"):
        ClaudeParser().parse_medical_document("some text")


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_sends_system_prompt_with_cache_control(MockAnthropic):
    tool_input = {"summary_he": "", "detected_category": "other", "suggested_tasks": []}
    MockAnthropic.return_value.messages.create.return_value = _response(
        _tool_block(tool_input)
    )

    ClaudeParser().parse_medical_document("text")

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    system = call_kwargs.kwargs["system"]
    assert isinstance(system, list)
    assert system[0]["cache_control"] == {"type": "ephemeral"}
