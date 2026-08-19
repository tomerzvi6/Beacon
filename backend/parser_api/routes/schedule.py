"""Calendar (יומן): appointments and other scheduled events."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import ScheduleEvent
from shared.schemas import ScheduleEventIn, ScheduleEventOut, ScheduleEventPatchIn

router = APIRouter(prefix="/v1/schedule", tags=["schedule"])


@router.get("/", response_model=list[ScheduleEventOut])
def list_events(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[ScheduleEventOut]:
    events = session.scalars(
        select(ScheduleEvent)
        .where(ScheduleEvent.household_id == uuid.UUID(user.household_id))
        .order_by(ScheduleEvent.starts_at.asc())
    ).all()
    return [ScheduleEventOut.model_validate(e) for e in events]


@router.post("/", response_model=ScheduleEventOut, status_code=status.HTTP_201_CREATED)
def create_event(
    body: ScheduleEventIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> ScheduleEventOut:
    # id/created_at set explicitly (not left to the column default) so the
    # response can be built right after add() without depending on flush
    # timing — same reasoning as routes/households.py's redeem_invite.
    event = ScheduleEvent(
        id=uuid.uuid4(),
        household_id=uuid.UUID(user.household_id),
        title=body.title,
        starts_at=body.starts_at,
        kind=body.kind,
        location_name=body.location_name,
        companion_user_id=body.companion_user_id,
        subtitle=body.subtitle,
        created_by=uuid.UUID(user.user_id),
        created_at=datetime.now(tz=timezone.utc),
    )
    session.add(event)
    session.commit()
    return ScheduleEventOut.model_validate(event)


@router.patch("/{event_id}", response_model=ScheduleEventOut)
def patch_event(
    event_id: str,
    body: ScheduleEventPatchIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> ScheduleEventOut:
    event = session.scalar(
        select(ScheduleEvent).where(
            ScheduleEvent.id == event_id,
            ScheduleEvent.household_id == uuid.UUID(user.household_id),
        )
    )
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    for field in ("title", "starts_at", "kind", "location_name", "companion_user_id", "subtitle"):
        value = getattr(body, field)
        if value is not None:
            setattr(event, field, value)

    session.commit()
    return ScheduleEventOut.model_validate(event)


@router.delete("/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_event(
    event_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> None:
    event = session.scalar(
        select(ScheduleEvent).where(
            ScheduleEvent.id == event_id,
            ScheduleEvent.household_id == uuid.UUID(user.household_id),
        )
    )
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    session.delete(event)
    session.commit()
