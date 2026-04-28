"""Claude Sonnet 4.6 integration for medical document parsing."""
import json

from anthropic import Anthropic

from parser_api.config import settings
from shared.schemas import SuggestedTask


class ClaudeParser:
    def __init__(self):
        self.client = Anthropic(api_key=settings.anthropic_api_key)

    def parse_medical_document(
        self,
        ocr_text: str,
        language: str = "he_IL",
    ) -> tuple[str, str, list[SuggestedTask]]:
        """
        Parse OCR'd medical document using Claude Sonnet 4.6 with structured output.
        Returns: (full_summary_he, simple_summary_he, suggested_tasks)
        """

        # System prompt with medical terminology context (cached for cost savings)
        system_prompt = """אתה מומחה בפענוח מסמכים רפואיים בעברית.
המטלה שלך:
1. לסכם את המסמך הרפואי בעברית בצורה מובנת
2. ליצור גרסה מפושטת עבור חולה/משפחה
3. לחלץ משימות פעולה ספציפיות בפורמט JSON structured output

דוגמאות משימות:
- "לתאם בדיקת CT בבית החולים"
- "לקחת זריקת Neulasta"
- "לתזמן בדיקת דם"

אל תכלול PHI (שמות חולים, מספרי רפואה) בסכומים."""

        message = self.client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=2000,
            system=[
                {
                    "type": "text",
                    "text": system_prompt,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            tools=[
                {
                    "name": "parse_medical_doc",
                    "description": "Extract summary and tasks from medical document",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "full_summary_he": {
                                "type": "string",
                                "description": "Full medical summary in Hebrew",
                            },
                            "simple_summary_he": {
                                "type": "string",
                                "description": "Patient-friendly summary in simple Hebrew",
                            },
                            "tasks": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "title_he": {"type": "string"},
                                        "category": {
                                            "type": "string",
                                            "enum": ["appointment", "medication", "test", "admin"],
                                        },
                                        "due_hint": {
                                            "type": "string",
                                            "description": "Natural language due date hint, e.g. 'תוך 3 ימים'",
                                        },
                                    },
                                    "required": ["title_he", "category"],
                                },
                                "description": "Suggested action items",
                            },
                        },
                        "required": ["full_summary_he", "simple_summary_he", "tasks"],
                    },
                }
            ],
            messages=[
                {
                    "role": "user",
                    "content": f"פענח מסמך רפואי זה:\n\n{ocr_text[:5000]}",  # Limit OCR to 5k chars
                }
            ],
        )

        # Extract tool use response
        tool_result = None
        for block in message.content:
            if hasattr(block, "type") and block.type == "tool_use":
                tool_result = block.input
                break

        if not tool_result:
            raise ValueError("Claude did not return structured output")

        full_summary = tool_result.get("full_summary_he", "")
        simple_summary = tool_result.get("simple_summary_he", "")
        tasks_raw = tool_result.get("tasks", [])

        suggested_tasks = [
            SuggestedTask(
                title_he=t.get("title_he", ""),
                category=t.get("category", "admin"),
                due_hint=t.get("due_hint"),
            )
            for t in tasks_raw
        ]

        return full_summary, simple_summary, suggested_tasks
