"""Medication dose tracking."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import AuditLog, DoseEvent

router = APIRouter(prefix="/v1/doses", tags=["doses"])


@router.post("/{dose_event_id}/taken")
def mark_dose_taken(
    dose_event_id: str,
    note_he: str | None = None,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> dict:
    """Mark a scheduled dose as taken."""
    dose = session.query(DoseEvent).filter(DoseEvent.id == dose_event_id).first()
    if not dose:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dose event not found")

    dose.taken_at = datetime.now(tz=timezone.utc)
    dose.note_he = note_he
    session.commit()

    # Get medication for audit context
    med = session.query(dose.medication).first()

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="mark_dose_taken",
            target_table="dose_events",
            target_id=dose.id,
            household_id=med.household_id if med else None,
        )
    )
    session.commit()

    return {"dose_event_id": str(dose_event_id), "taken_at": dose.taken_at}
