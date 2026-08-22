"""xAI Grok — category-routed medical document parsing.

Mirrors claude_parser.py's public interface exactly (same
parse_medical_document signature and return shape), so
parser_api.routes.documents.parse_document only needs its import changed,
not rewritten. Kept as a separate module rather than a rewrite of
claude_parser.py so switching back to Claude is a one-line import change.

xAI's API is OpenAI-compatible (base_url=https://api.x.ai/v1), so this uses
the `openai` SDK rather than a dedicated xai-sdk. The tool definitions
themselves are NOT duplicated — they're imported from services/prompts/
(shared with claude_parser.py) and adapted from Anthropic's tool shape
(name/description/input_schema) to OpenAI's (type=function,
function={name/description/parameters}) at the call boundary in
_to_openai_tool().

Model note: pricing writeups advertised a "Grok 4 Fast" budget tier, but
GET /v1/models against the real account only returns grok-4.3 / 4.5 / 4.6 /
4.20-* / build-0.1 — no "fast" variant exists on this key. grok-4.3 is used
here as the least expensive of the confirmed-available general-purpose
models ($1.25/$2.50 per 1M tokens, 1M context).
"""
import json
from typing import Optional

from openai import OpenAI

from parser_api.config import settings
from parser_api.services.prompts import (
    SYSTEM_BASE,
    ADMIN_TOOL, ADMIN_USER_TMPL,
    LAB_TOOL, LAB_USER_TMPL,
    PRESCRIPTION_TOOL, PRESCRIPTION_USER_TMPL,
    IMAGING_TOOL, IMAGING_USER_TMPL,
    DEFAULT_TOOL, DEFAULT_USER_TMPL,
)
from shared.schemas import SuggestedTask

_GROK = "grok-4.3"

# (model, tool_def, user_template, default_task_category)
_ROUTE: dict[str, tuple[str, dict, str, str]] = {
    "admin":        (_GROK, ADMIN_TOOL,        ADMIN_USER_TMPL,        "admin"),
    "lab":          (_GROK, LAB_TOOL,           LAB_USER_TMPL,          "test"),
    "prescription": (_GROK, PRESCRIPTION_TOOL,  PRESCRIPTION_USER_TMPL, "medication"),
    "imaging":      (_GROK, IMAGING_TOOL,       IMAGING_USER_TMPL,      "appointment"),
    "consult":      (_GROK, IMAGING_TOOL,       IMAGING_USER_TMPL,      "appointment"),
    "referral":     (_GROK, IMAGING_TOOL,       IMAGING_USER_TMPL,      "appointment"),
}
_DEFAULT_ROUTE = (_GROK, DEFAULT_TOOL, DEFAULT_USER_TMPL, "admin")


def _to_openai_tool(anthropic_tool: dict) -> dict:
    return {
        "type": "function",
        "function": {
            "name": anthropic_tool["name"],
            "description": anthropic_tool["description"],
            "parameters": anthropic_tool["input_schema"],
        },
    }


class GrokParser:
    def __init__(self):
        self.client = OpenAI(api_key=settings.xai_api_key, base_url="https://api.x.ai/v1")

    def parse_medical_document(
        self,
        ocr_text: str,
        category: Optional[str] = None,
        language: str = "he_IL",
    ) -> tuple[str, str, list[SuggestedTask], str]:
        """
        Category-routed parse via Grok. Returns:
        (full_summary_he, simple_summary_he, suggested_tasks, model_suggested_category)
        """
        model, tool, user_tmpl, task_cat = _ROUTE.get(category or "", _DEFAULT_ROUTE)
        function_name = tool["name"]

        completion = self.client.chat.completions.create(
            model=model,
            max_tokens=2000,
            messages=[
                {"role": "system", "content": SYSTEM_BASE},
                {"role": "user", "content": user_tmpl.format(ocr_text=ocr_text[:5000])},
            ],
            tools=[_to_openai_tool(tool)],
            tool_choice={"type": "function", "function": {"name": function_name}},
        )

        message = completion.choices[0].message
        tool_calls = message.tool_calls or []
        if not tool_calls:
            raise ValueError("Grok did not return structured output")

        tool_result = json.loads(tool_calls[0].function.arguments)

        summary_he = tool_result.get("summary_he", "")
        detected_category = tool_result.get("detected_category", category or "other")

        raw_tasks = tool_result.get("suggested_tasks", [])
        suggested_tasks = [
            SuggestedTask(
                title_he=t.get("title_he", ""),
                category=task_cat,
                due_hint=t.get("due_date") or t.get("due_hint"),
            )
            for t in raw_tasks
        ]

        return summary_he, summary_he, suggested_tasks, detected_category
