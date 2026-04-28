"""Symptom reporting (דיווח מהיר)."""
import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import AuditLog, SymptomReport
from shared.schemas import SymptomReportIn, SymptomReportOut

router = APIRouter(prefix="/v1/symptoms", tags=["symptoms"])


@router.post("/", response_model=SymptomReportOut)
def report_symptom(
    payload: SymptomReportIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> SymptomReportOut:
    """Record a quick symptom report (nausea, fatigue, pain)."""
    report = SymptomReport(
        household_id=uuid.UUID(user.household_id),
        kind=payload.kind,
        severity=payload.severity,
        note_he=payload.note_he,
    )
    session.add(report)
    session.commit()

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="report_symptom",
            target_table="symptom_reports",
            target_id=report.id,
            household_id=report.household_id,
        )
    )
    session.commit()

    return SymptomReportOut.model_validate(report)
