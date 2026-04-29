"""Prescription documents — drug name, dose, frequency, duration."""

PRESCRIPTION_USER_TMPL = "פענח מרשם תרופות. חלץ: שם תרופה, מינון, תדירות, משך טיפול:\n\n{ocr_text}"

PRESCRIPTION_TOOL = {
    "name": "parse_prescription_doc",
    "description": "Extract medication details from a prescription",
    "input_schema": {
        "type": "object",
        "properties": {
            "summary_he": {
                "type": "string",
                "description": "One-line Hebrew summary: drug(s), dose, duration",
            },
            "document_date": {
                "type": "string",
                "description": "ISO date of prescription, else null",
            },
            "provider_name": {
                "type": "string",
                "description": "Prescribing clinic/doctor practice name (no patient name)",
            },
            "medications": {
                "type": "array",
                "description": "Each prescribed drug",
                "items": {
                    "type": "object",
                    "properties": {
                        "drug_name_he": {"type": "string", "description": "Hebrew drug name"},
                        "drug_name_generic": {"type": "string", "description": "Generic/INN name if identifiable"},
                        "dose": {"type": "string", "description": "e.g. '500mg'"},
                        "frequency": {"type": "string", "description": "e.g. 'פעמיים ביום'"},
                        "duration": {"type": "string", "description": "e.g. '7 ימים' or null if chronic"},
                        "route": {"type": "string", "description": "e.g. 'פה', 'IV', 'עור'"},
                        "instructions": {"type": "string", "description": "Special instructions (with food, etc.)"},
                    },
                    "required": ["drug_name_he", "dose", "frequency"],
                },
            },
            "suggested_tasks": {
                "type": "array",
                "description": "Reminders to fill/start/stop medication — one task per drug or key reminder",
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
