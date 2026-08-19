"""Caregiver layer (שכבת מטפל/ת): home-aide profiles, check-ins, family instructions.

The caregiver has no login — the family maintains the profile and reads
check-ins; the caregiver reports through a code-free screen shared on a
family member's device, so every write here is authenticated as the family
member, not the caregiver.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from parser_api.services.notify import notify_household
from shared.models import AuditLog, CaregiverCheckIn, CaregiverInstruction, CaregiverProfile, User
from shared.schemas import (
    CaregiverCheckInIn,
    CaregiverCheckInOut,
    CaregiverInstructionIn,
    CaregiverInstructionOut,
    CaregiverInstructionPatchIn,
    CaregiverProfileIn,
    CaregiverProfileOut,
    CaregiverProfilePatchIn,
)

router = APIRouter(prefix="/v1/caregivers", tags=["caregivers"])


# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------


@router.get("/profiles", response_model=list[CaregiverProfileOut])
def list_profiles(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[CaregiverProfileOut]:
    profiles = session.scalars(
        select(CaregiverProfile).where(
            CaregiverProfile.household_id == uuid.UUID(user.household_id)
        )
    ).all()
    return [CaregiverProfileOut.model_validate(p) for p in profiles]


@router.post("/profiles", response_model=CaregiverProfileOut, status_code=status.HTTP_201_CREATED)
def create_profile(
    body: CaregiverProfileIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> CaregiverProfileOut:
    profile = CaregiverProfile(
        id=uuid.uuid4(),
        household_id=uuid.UUID(user.household_id),
        display_name=body.display_name,
        relation_title=body.relation_title,
        preferred_language=body.preferred_language,
        created_by=uuid.UUID(user.user_id),
        created_at=datetime.now(tz=timezone.utc),
    )
    session.add(profile)
    session.commit()
    return CaregiverProfileOut.model_validate(profile)


@router.patch("/profiles/{profile_id}", response_model=CaregiverProfileOut)
def patch_profile(
    profile_id: str,
    body: CaregiverProfilePatchIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> CaregiverProfileOut:
    profile = session.scalar(
        select(CaregiverProfile).where(
            CaregiverProfile.id == profile_id,
            CaregiverProfile.household_id == uuid.UUID(user.household_id),
        )
    )
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Caregiver not found")

    for field in ("display_name", "relation_title", "preferred_language", "is_active"):
        value = getattr(body, field)
        if value is not None:
            setattr(profile, field, value)

    session.commit()
    return CaregiverProfileOut.model_validate(profile)


# ---------------------------------------------------------------------------
# Check-ins
# ---------------------------------------------------------------------------


@router.get("/checkins", response_model=list[CaregiverCheckInOut])
def list_checkins(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[CaregiverCheckInOut]:
    checkins = session.scalars(
        select(CaregiverCheckIn)
        .where(CaregiverCheckIn.household_id == uuid.UUID(user.household_id))
        .order_by(CaregiverCheckIn.created_at.desc())
    ).all()
    return [CaregiverCheckInOut.model_validate(c) for c in checkins]


@router.post("/checkins", response_model=CaregiverCheckInOut, status_code=status.HTTP_201_CREATED)
def create_checkin(
    body: CaregiverCheckInIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> CaregiverCheckInOut:
    profile = session.scalar(
        select(CaregiverProfile).where(
            CaregiverProfile.id == body.caregiver_id,
            CaregiverProfile.household_id == uuid.UUID(user.household_id),
        )
    )
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Caregiver not found")

    checkin = CaregiverCheckIn(
        id=uuid.uuid4(),
        household_id=uuid.UUID(user.household_id),
        caregiver_id=profile.id,
        meal_status=body.meal_status,
        hydration_status=body.hydration_status,
        sleep_status=body.sleep_status,
        pain_level=body.pain_level,
        nausea_level=body.nausea_level,
        fatigue_level=body.fatigue_level,
        medication_status=body.medication_status,
        medication_note=body.medication_note,
        free_text_original=body.free_text_original,
        original_language=body.original_language,
        translated_summary_hebrew=body.translated_summary_hebrew,
        attention_level=body.attention_level,
        alert_reasons=body.alert_reasons,
        is_acknowledged=False,
        created_at=datetime.now(tz=timezone.utc),
    )
    session.add(checkin)
    session.commit()

    if checkin.attention_level != "ok":
        session.add(AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="caregiver_checkin_flagged",
            target_table="caregiver_checkins",
            target_id=checkin.id,
            household_id=checkin.household_id,
            metadata_={"attention_level": checkin.attention_level, "reasons": checkin.alert_reasons},
        ))
        session.commit()

        level_label = "דחוף" if checkin.attention_level == "urgent" else "דורש תשומת לב"
        notify_household(
            session, checkin.household_id,
            title=f"עדכון מהמטפל/ת — {level_label}",
            body=checkin.translated_summary_hebrew[:120],
            exclude_user_id=uuid.UUID(user.user_id),
        )

    return CaregiverCheckInOut.model_validate(checkin)


@router.post("/checkins/{checkin_id}/acknowledge", response_model=CaregiverCheckInOut)
def acknowledge_checkin(
    checkin_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> CaregiverCheckInOut:
    checkin = session.scalar(
        select(CaregiverCheckIn).where(
            CaregiverCheckIn.id == checkin_id,
            CaregiverCheckIn.household_id == uuid.UUID(user.household_id),
        )
    )
    if not checkin:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Check-in not found")
    checkin.is_acknowledged = True
    session.commit()
    return CaregiverCheckInOut.model_validate(checkin)


# ---------------------------------------------------------------------------
# Instructions (family → caregiver)
# ---------------------------------------------------------------------------


def _instruction_out(instruction: CaregiverInstruction, name: str) -> CaregiverInstructionOut:
    return CaregiverInstructionOut(
        id=instruction.id,
        kind=instruction.kind,
        detail=instruction.detail,
        created_by_name=name,
        is_active=instruction.is_active,
        created_at=instruction.created_at,
    )


@router.get("/instructions", response_model=list[CaregiverInstructionOut])
def list_instructions(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[CaregiverInstructionOut]:
    rows = session.execute(
        select(CaregiverInstruction, User.display_name)
        .join(User, User.id == CaregiverInstruction.created_by)
        .where(
            CaregiverInstruction.household_id == uuid.UUID(user.household_id),
            CaregiverInstruction.is_active.is_(True),
        )
        .order_by(CaregiverInstruction.created_at.desc())
    ).all()
    return [_instruction_out(instruction, name) for instruction, name in rows]


@router.post("/instructions", response_model=CaregiverInstructionOut, status_code=status.HTTP_201_CREATED)
def create_instruction(
    body: CaregiverInstructionIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> CaregiverInstructionOut:
    instruction = CaregiverInstruction(
        id=uuid.uuid4(),
        household_id=uuid.UUID(user.household_id),
        kind=body.kind,
        detail=body.detail,
        created_by=uuid.UUID(user.user_id),
        is_active=True,
        created_at=datetime.now(tz=timezone.utc),
    )
    session.add(instruction)
    session.commit()

    name = session.scalar(select(User.display_name).where(User.id == uuid.UUID(user.user_id)))
    return _instruction_out(instruction, name or "")


@router.patch("/instructions/{instruction_id}", response_model=CaregiverInstructionOut)
def patch_instruction(
    instruction_id: str,
    body: CaregiverInstructionPatchIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> CaregiverInstructionOut:
    instruction = session.scalar(
        select(CaregiverInstruction).where(
            CaregiverInstruction.id == instruction_id,
            CaregiverInstruction.household_id == uuid.UUID(user.household_id),
        )
    )
    if not instruction:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Instruction not found")
    if body.is_active is not None:
        instruction.is_active = body.is_active
    session.commit()

    name = session.scalar(select(User.display_name).where(User.id == instruction.created_by))
    return _instruction_out(instruction, name or "")
