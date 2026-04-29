"""Claude Sonnet 4.6 / Haiku 4.5 — category-routed medical document parsing."""
from typing import Optional

from anthropic import Anthropic

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

_SONNET = "claude-sonnet-4-6"
_HAIKU = "claude-haiku-4-5-20251001"

# (model, tool_def, user_template, default_task_category)
_ROUTE: dict[str, tuple[str, dict, str, str]] = {
    "admin":        (_HAIKU,   ADMIN_TOOL,        ADMIN_USER_TMPL,        "admin"),
    "lab":          (_SONNET,  LAB_TOOL,           LAB_USER_TMPL,          "test"),
    "prescription": (_SONNET,  PRESCRIPTION_TOOL,  PRESCRIPTION_USER_TMPL, "medication"),
    "imaging":      (_SONNET,  IMAGING_TOOL,       IMAGING_USER_TMPL,      "appointment"),
    "consult":      (_SONNET,  IMAGING_TOOL,       IMAGING_USER_TMPL,      "appointment"),
    "referral":     (_SONNET,  IMAGING_TOOL,       IMAGING_USER_TMPL,      "appointment"),
}
_DEFAULT_ROUTE = (_SONNET, DEFAULT_TOOL, DEFAULT_USER_TMPL, "admin")


class ClaudeParser:
    def __init__(self):
        self.client = Anthropic(api_key=settings.anthropic_api_key)

    def parse_medical_document(
        self,
        ocr_text: str,
        category: Optional[str] = None,
        language: str = "he_IL",
    ) -> tuple[str, str, list[SuggestedTask], str]:
        """
        Category-routed parse. Admin → Haiku; all others → Sonnet.

        Returns: (full_summary_he, simple_summary_he, suggested_tasks, model_suggested_category)
        """
        model, tool, user_tmpl, task_cat = _ROUTE.get(category or "", _DEFAULT_ROUTE)

        message = self.client.messages.create(
            model=model,
            max_tokens=2000,
            system=[
                {
                    "type": "text",
                    "text": SYSTEM_BASE,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            tools=[tool],
            tool_choice={"type": "any"},
            messages=[
                {
                    "role": "user",
                    "content": user_tmpl.format(ocr_text=ocr_text[:5000]),
                }
            ],
        )

        tool_result = None
        for block in message.content:
            if hasattr(block, "type") and block.type == "tool_use":
                tool_result = block.input
                break

        if not tool_result:
            raise ValueError("Claude did not return structured output")

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
