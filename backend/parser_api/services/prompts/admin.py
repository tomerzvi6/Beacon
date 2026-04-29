"""Admin documents — metadata only, no tasks. Uses Haiku for cost savings."""

ADMIN_USER_TMPL = "פענח מסמך אדמיניסטרטיבי. חלץ רק מטא-דאטה:\n\n{ocr_text}"

ADMIN_TOOL = {
    "name": "parse_admin_doc",
    "description": "Extract metadata from an administrative medical document",
    "input_schema": {
        "type": "object",
        "properties": {
            "summary_he": {
                "type": "string",
                "description": "One-line Hebrew summary (date, provider, amount/reference if present)",
            },
            "document_date": {
                "type": "string",
                "description": "ISO date if found, else null",
            },
            "provider_name": {
                "type": "string",
                "description": "Clinic/hospital name if mentioned (no patient name)",
            },
            "amount": {
                "type": "string",
                "description": "Monetary amount if relevant (receipts, invoices)",
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
