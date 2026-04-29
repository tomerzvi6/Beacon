"""Lab results — focused on values and abnormals. No medication tasks."""

LAB_USER_TMPL = "פענח תוצאות מעבדה. חלץ ערכים ודגלי חריגות בלבד:\n\n{ocr_text}"

LAB_TOOL = {
    "name": "parse_lab_doc",
    "description": "Extract lab values and abnormal flags from a lab results document",
    "input_schema": {
        "type": "object",
        "properties": {
            "summary_he": {
                "type": "string",
                "description": "One-line Hebrew summary: key findings, date, ordering provider if present",
            },
            "document_date": {
                "type": "string",
                "description": "ISO date of the test, else null",
            },
            "provider_name": {
                "type": "string",
                "description": "Lab or ordering clinic name (no patient name)",
            },
            "lab_values": {
                "type": "array",
                "description": "List of individual lab measurements",
                "items": {
                    "type": "object",
                    "properties": {
                        "test_name": {"type": "string"},
                        "value": {"type": "string"},
                        "unit": {"type": "string"},
                        "reference_range": {"type": "string"},
                        "is_abnormal": {"type": "boolean"},
                        "direction": {
                            "type": "string",
                            "enum": ["high", "low", "normal", "unknown"],
                        },
                    },
                    "required": ["test_name", "value", "is_abnormal"],
                },
            },
            "abnormal_flags": {
                "type": "array",
                "description": "Short Hebrew phrases for each out-of-range result",
                "items": {"type": "string"},
            },
            "suggested_tasks": {
                "type": "array",
                "description": "Follow-up actions (e.g., repeat test, specialist consult) — NOT medication instructions",
                "items": {
                    "type": "object",
                    "properties": {
                        "title_he": {"type": "string"},
                        "due_date": {"type": "string", "description": "ISO date or null"},
                        "priority": {"type": "string", "enum": ["high", "medium", "low"]},
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
