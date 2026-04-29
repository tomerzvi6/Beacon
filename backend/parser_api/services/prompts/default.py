"""Default / visit_summary / other — full structured parse (current behavior)."""

DEFAULT_USER_TMPL = "פענח מסמך רפואי. חלץ תקציר, משימות טיפול ומטא-דאטה:\n\n{ocr_text}"

DEFAULT_TOOL = {
    "name": "parse_medical_doc",
    "description": "Full structured extraction from a general medical document",
    "input_schema": {
        "type": "object",
        "properties": {
            "summary_he": {
                "type": "string",
                "description": "2-4 sentence Hebrew summary: purpose, findings, plan",
            },
            "document_date": {
                "type": "string",
                "description": "ISO date if found, else null",
            },
            "provider_name": {
                "type": "string",
                "description": "Clinic/hospital/doctor practice name (no patient name)",
            },
            "diagnoses": {
                "type": "array",
                "description": "Active diagnoses or new findings mentioned",
                "items": {"type": "string"},
            },
            "suggested_tasks": {
                "type": "array",
                "description": "Actionable care tasks for the patient/family",
                "items": {
                    "type": "object",
                    "properties": {
                        "title_he": {"type": "string"},
                        "due_date": {"type": "string", "description": "ISO date or null"},
                        "priority": {"type": "string", "enum": ["high", "medium", "low"]},
                        "is_urgent": {"type": "boolean"},
                    },
                    "required": ["title_he", "priority"],
                },
            },
            "follow_up_date": {
                "type": "string",
                "description": "Scheduled next-visit ISO date if mentioned",
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
