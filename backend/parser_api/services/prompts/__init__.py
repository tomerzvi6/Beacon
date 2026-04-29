"""Prompt templates for category-routed document parsing."""
from parser_api.services.prompts.base import SYSTEM_BASE
from parser_api.services.prompts.admin import ADMIN_TOOL, ADMIN_USER_TMPL
from parser_api.services.prompts.lab import LAB_TOOL, LAB_USER_TMPL
from parser_api.services.prompts.prescription import PRESCRIPTION_TOOL, PRESCRIPTION_USER_TMPL
from parser_api.services.prompts.imaging import IMAGING_TOOL, IMAGING_USER_TMPL
from parser_api.services.prompts.default import DEFAULT_TOOL, DEFAULT_USER_TMPL

__all__ = [
    "SYSTEM_BASE",
    "ADMIN_TOOL", "ADMIN_USER_TMPL",
    "LAB_TOOL", "LAB_USER_TMPL",
    "PRESCRIPTION_TOOL", "PRESCRIPTION_USER_TMPL",
    "IMAGING_TOOL", "IMAGING_USER_TMPL",
    "DEFAULT_TOOL", "DEFAULT_USER_TMPL",
]
