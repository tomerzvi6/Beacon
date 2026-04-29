"""Imaging / consult / referral documents — action recommendations and dates."""

IMAGING_USER_TMPL = (
    "פענח מסמך הדמיה / ייעוץ / הפניה. "
    "חלץ: ממצאים עיקריים, המלצות פעולה ותאריכים:\n\n{ocr_text}"
)

IMAGING_TOOL = {
    "name": "parse_imaging_doc",
    "description": "Extract findings and action items from imaging reports, consults, and referrals",
    "input_schema": {
        "type": "object",
        "properties": {
            "summary_he": {
                "type": "string",
                "description": "One-line Hebrew summary: modality/type, key finding, recommended action",
            },
            "document_date": {
                "type": "string",
                "description": "ISO date of the exam/consult, else null",
            },
            "provider_name": {
                "type": "string",
                "description": "Imaging center, hospital dept, or consulting specialist name (no patient name)",
            },
            "modality_or_type": {
                "type": "string",
                "description": "e.g. CT, MRI, X-ray, אולטרסאונד, ייעוץ קרדיולוגי, הפניה לאורתופד",
            },
            "body_region": {
                "type": "string",
                "description": "Anatomical area (e.g. חזה, בטן, ראש) or specialty for consults",
            },
            "key_findings": {
                "type": "array",
                "description": "Main findings in brief Hebrew phrases",
                "items": {"type": "string"},
            },
            "impression": {
                "type": "string",
                "description": "Radiologist/specialist impression/conclusion if present",
            },
            "suggested_tasks": {
                "type": "array",
                "description": "Follow-up actions: schedule, repeat, refer, or urgent escalation",
                "items": {
                    "type": "object",
                    "properties": {
                        "title_he": {"type": "string"},
                        "due_date": {"type": "string", "description": "ISO date or null"},
                        "priority": {"type": "string", "enum": ["high", "medium", "low"]},
                        "is_urgent": {
                            "type": "boolean",
                            "description": "True if report explicitly marks as urgent",
                        },
                    },
                    "required": ["title_he", "priority"],
                },
            },
            "detected_category": {
                "type": "string",
                "enum": ["lab", "prescription", "visit_summary", "referral",
                         "imaging", "consult", "admin", "other"],
            },
        },
        "required": ["summary_he", "detected_category"],
    },
}
