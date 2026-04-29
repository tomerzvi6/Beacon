"""Unit tests for ClaudeParser — mocks the Anthropic SDK so no real API calls are made."""
import types
from unittest.mock import MagicMock, patch

import pytest

from parser_api.services.claude_parser import ClaudeParser
from shared.schemas import SuggestedTask


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_tool_use_block(tool_input: dict) -> MagicMock:
    block = MagicMock()
    block.type = "tool_use"
    block.input = tool_input
    return block


def _make_text_block(text: str = "thinking…") -> MagicMock:
    block = MagicMock()
    block.type = "text"
    block.text = text
    return block


def _fake_response(*blocks) -> MagicMock:
    msg = MagicMock()
    msg.content = list(blocks)
    return msg


# ---------------------------------------------------------------------------
# Happy-path tests
# ---------------------------------------------------------------------------


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_returns_summaries_and_tasks(MockAnthropic):
    tool_input = {
        "full_summary_he": "סיכום מלא של המסמך",
        "simple_summary_he": "סיכום פשוט",
        "tasks": [
            {"title_he": "לתאם בדיקת CT", "category": "test", "due_hint": "תוך שבוע"},
            {"title_he": "לקחת זריקת Neulasta", "category": "medication"},
        ],
    }
    MockAnthropic.return_value.messages.create.return_value = _fake_response(
        _make_text_block(), _make_tool_use_block(tool_input)
    )

    parser = ClaudeParser()
    full, simple, tasks = parser.parse_medical_document("sample ocr text")

    assert full == "סיכום מלא של המסמך"
    assert simple == "סיכום פשוט"
    assert len(tasks) == 2
    assert isinstance(tasks[0], SuggestedTask)
    assert tasks[0].title_he == "לתאם בדיקת CT"
    assert tasks[0].category == "test"
    assert tasks[0].due_hint == "תוך שבוע"
    assert tasks[1].due_hint is None


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_empty_tasks_list(MockAnthropic):
    tool_input = {
        "full_summary_he": "ממצאים תקינים",
        "simple_summary_he": "הכל בסדר",
        "tasks": [],
    }
    MockAnthropic.return_value.messages.create.return_value = _fake_response(
        _make_tool_use_block(tool_input)
    )

    parser = ClaudeParser()
    full, simple, tasks = parser.parse_medical_document("normal scan")

    assert tasks == []
    assert full == "ממצאים תקינים"


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_truncates_long_ocr_to_5000_chars(MockAnthropic):
    """Claude is called with at most 5 000 characters of OCR text."""
    tool_input = {
        "full_summary_he": "x",
        "simple_summary_he": "y",
        "tasks": [],
    }
    MockAnthropic.return_value.messages.create.return_value = _fake_response(
        _make_tool_use_block(tool_input)
    )

    parser = ClaudeParser()
    long_text = "א" * 10_000
    parser.parse_medical_document(long_text)

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    user_content = call_kwargs.kwargs["messages"][0]["content"]
    # The content string ends with the (sliced) OCR text
    assert len(user_content) <= 5100  # 5000 chars + short prefix


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_raises_if_no_tool_use_block(MockAnthropic):
    MockAnthropic.return_value.messages.create.return_value = _fake_response(
        _make_text_block("I cannot help with that.")
    )

    parser = ClaudeParser()
    with pytest.raises(ValueError, match="structured output"):
        parser.parse_medical_document("some text")


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_uses_claude_sonnet_4_6(MockAnthropic):
    tool_input = {"full_summary_he": "", "simple_summary_he": "", "tasks": []}
    MockAnthropic.return_value.messages.create.return_value = _fake_response(
        _make_tool_use_block(tool_input)
    )

    parser = ClaudeParser()
    parser.parse_medical_document("text")

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    assert call_kwargs.kwargs["model"] == "claude-sonnet-4-6"


@patch("parser_api.services.claude_parser.Anthropic")
def test_parse_sends_system_prompt_with_cache_control(MockAnthropic):
    tool_input = {"full_summary_he": "", "simple_summary_he": "", "tasks": []}
    MockAnthropic.return_value.messages.create.return_value = _fake_response(
        _make_tool_use_block(tool_input)
    )

    parser = ClaudeParser()
    parser.parse_medical_document("text")

    call_kwargs = MockAnthropic.return_value.messages.create.call_args
    system = call_kwargs.kwargs["system"]
    assert isinstance(system, list)
    assert system[0]["cache_control"] == {"type": "ephemeral"}
