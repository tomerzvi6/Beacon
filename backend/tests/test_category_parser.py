"""Unit tests for category-routed ClaudeParser."""
from unittest.mock import MagicMock, patch

import pytest

from parser_api.services.claude_parser import ClaudeParser, _HAIKU, _SONNET
from parser_api.services.prompts import (
    ADMIN_TOOL,
    LAB_TOOL,
    PRESCRIPTION_TOOL,
    IMAGING_TOOL,
    DEFAULT_TOOL,
)


def _tool_block(tool_input: dict) -> MagicMock:
    b = MagicMock()
    b.type = "tool_use"
    b.input = tool_input
    return b


def _response(tool_input: dict) -> MagicMock:
    msg = MagicMock()
    msg.content = [_tool_block(tool_input)]
    return msg


# ---------------------------------------------------------------------------
# Model routing
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("category,expected_model", [
    ("admin", _HAIKU),
    ("lab", _SONNET),
    ("prescription", _SONNET),
    ("imaging", _SONNET),
    ("consult", _SONNET),
    ("referral", _SONNET),
    ("visit_summary", _SONNET),
    (None, _SONNET),
])
@patch("parser_api.services.claude_parser.Anthropic")
def test_category_routes_to_correct_model(MockAnthropic, category, expected_model):
    MockAnthropic.return_value.messages.create.return_value = _response(
        {"summary_he": "x", "detected_category": category or "other", "suggested_tasks": []}
    )
    ClaudeParser().parse_medical_document("text", category=category)
    kwargs = MockAnthropic.return_value.messages.create.call_args.kwargs
    assert kwargs["model"] == expected_model


# ---------------------------------------------------------------------------
# Tool routing
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("category,expected_tool_name", [
    ("admin", "parse_admin_doc"),
    ("lab", "parse_lab_doc"),
    ("prescription", "parse_prescription_doc"),
    ("imaging", "parse_imaging_doc"),
    ("consult", "parse_imaging_doc"),
    ("referral", "parse_imaging_doc"),
    ("visit_summary", "parse_medical_doc"),
    (None, "parse_medical_doc"),
])
@patch("parser_api.services.claude_parser.Anthropic")
def test_category_routes_to_correct_tool(MockAnthropic, category, expected_tool_name):
    MockAnthropic.return_value.messages.create.return_value = _response(
        {"summary_he": "x", "detected_category": category or "other", "suggested_tasks": []}
    )
    ClaudeParser().parse_medical_document("text", category=category)
    kwargs = MockAnthropic.return_value.messages.create.call_args.kwargs
    assert kwargs["tools"][0]["name"] == expected_tool_name


# ---------------------------------------------------------------------------
# Return value
# ---------------------------------------------------------------------------


@patch("parser_api.services.claude_parser.Anthropic")
def test_returns_four_tuple(MockAnthropic):
    MockAnthropic.return_value.messages.create.return_value = _response(
        {"summary_he": "תוצאות תקינות", "detected_category": "lab", "suggested_tasks": []}
    )
    result = ClaudeParser().parse_medical_document("text", category="lab")
    assert len(result) == 4
    full, simple, tasks, cat = result
    assert full == "תוצאות תקינות"
    assert cat == "lab"
    assert tasks == []


@patch("parser_api.services.claude_parser.Anthropic")
def test_task_category_derived_from_document_category(MockAnthropic):
    MockAnthropic.return_value.messages.create.return_value = _response({
        "summary_he": "מרשם",
        "detected_category": "prescription",
        "suggested_tasks": [{"title_he": "לקחת אוגמנטין", "priority": "high"}],
    })
    _, _, tasks, _ = ClaudeParser().parse_medical_document("rx", category="prescription")
    assert tasks[0].category == "medication"


@patch("parser_api.services.claude_parser.Anthropic")
def test_tool_choice_any_is_set(MockAnthropic):
    MockAnthropic.return_value.messages.create.return_value = _response(
        {"summary_he": "", "detected_category": "other", "suggested_tasks": []}
    )
    ClaudeParser().parse_medical_document("text")
    kwargs = MockAnthropic.return_value.messages.create.call_args.kwargs
    assert kwargs.get("tool_choice") == {"type": "any"}
