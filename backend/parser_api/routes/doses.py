"""Medication dose tracking."""
import uuid
from datetime import datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import AuditLog, DoseEvent, Medication
from shared.schemas import DoseEventOut

router = APIRouter(prefix="/v1/doses", tags=["doses"])


def _dose_status(dose: DoseEvent, now: datetime) -> str:
    if dose.taken_at is not None:
        return "taken"
    if dose.scheduled_at < now:
        return "missed"
    return "upcoming"


def _to_out(dose: DoseEvent, now: datetime) -> DoseEventOut:
    return DoseEventOut(
        id=dose.id,
        medication_id=dose.medication_id,
        scheduled_at=dose.scheduled_at,
        taken_at=dose.taken_at,
        note_he=dose.note_he,
        status=_dose_status(dose, now),
    )


@router.get("/", response_model=list[DoseEventOut])
def list_doses(
    from_date: datetime | None = None,
    to_date: datetime | None = None,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[DoseEventOut]:
    """List dose events for the household, optionally bounded by a date range.
    Defaults to today (00:00–24:00 UTC) when no range is given, matching the
    app's "today's doses" screen."""
    now = datetime.now(tz=timezone.utc)
    if from_date is None:
        from_date = now.replace(hour=0, minute=0, second=0, microsecond=0)
    if to_date is None:
        to_date = from_date + timedelta(days=1)

    doses = session.scalars(
        select(DoseEvent)
        .join(Medication, DoseEvent.medication_id == Medication.id)
        .where(
            Medication.household_id == uuid.UUID(user.household_id),
            DoseEvent.scheduled_at >= from_date,
            DoseEvent.scheduled_at < to_date,
        )
        .order_by(DoseEvent.scheduled_at.asc())
    ).all()
    return [_to_out(d, now) for d in doses]


@router.post("/materialize-today", response_model=list[DoseEventOut])
def materialize_today(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[DoseEventOut]:
    """Create today's DoseEvent rows from each medication's recurring
    schedule (schedule.dosing_times = ["HH:MM", ...]). Idempotent: skips any
    slot that already has a dose event for today. Call this once per app
    session/day so every device sees the same generated doses, rather than
    each device materializing its own local copy.
    """
    now = datetime.now(tz=timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = today_start + timedelta(days=1)

    meds = session.scalars(
        select(Medication).where(Medication.household_id == uuid.UUID(user.household_id))
    ).all()

    existing = session.scalars(
        select(DoseEvent)
        .join(Medication, DoseEvent.medication_id == Medication.id)
        .where(
            Medication.household_id == uuid.UUID(user.household_id),
            DoseEvent.scheduled_at >= today_start,
            DoseEvent.scheduled_at < today_end,
        )
    ).all()
    existing_slots = {(d.medication_id, d.scheduled_at) for d in existing}

    created: list[DoseEvent] = []
    for med in meds:
        for raw_time in med.schedule.get("dosing_times", []):
            try:
                hour, minute = (int(part) for part in raw_time.split(":"))
                slot_time = time(hour=hour, minute=minute)
            except (ValueError, TypeError):
                continue
            scheduled_at = datetime.combine(today_start.date(), slot_time, tzinfo=timezone.utc)
            if (med.id, scheduled_at) in existing_slots:
                continue
            dose = DoseEvent(id=uuid.uuid4(), medication_id=med.id, scheduled_at=scheduled_at)
            session.add(dose)
            created.append(dose)

    if created:
        session.commit()

    all_today = existing + created
    all_today.sort(key=lambda d: d.scheduled_at)
    return [_to_out(d, now) for d in all_today]


@router.post("/{dose_event_id}/taken")
def mark_dose_taken(
    dose_event_id: str,
    note_he: str | None = None,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> dict:
    """Mark a scheduled dose as taken."""
    dose = (
        session.query(DoseEvent)
        .join(Medication, DoseEvent.medication_id == Medication.id)
        .filter(
            DoseEvent.id == dose_event_id,
            Medication.household_id == uuid.UUID(user.household_id),
        )
        .first()
    )
    if not dose:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dose event not found")

    dose.taken_at = datetime.now(tz=timezone.utc)
    dose.note_he = note_he
    session.commit()

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="mark_dose_taken",
            target_table="dose_events",
            target_id=dose.id,
            household_id=dose.medication.household_id,
        )
    )
    session.commit()

    return {"dose_event_id": str(dose_event_id), "taken_at": dose.taken_at}
