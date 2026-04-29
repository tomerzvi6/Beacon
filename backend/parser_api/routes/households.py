"""Household membership: co-owner invite (2-step) and caregiver invite (open code)."""
import hashlib
import logging
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.config import settings
from parser_api.dependencies import get_session, get_user_context, require_roles
from shared.models import AuditLog, HouseholdInvite, HouseholdMember
from shared.schemas import (
    CaregiverInviteOut,
    CaregiverJoinIn,
    CoOwnerAcceptIn,
    CoOwnerInviteIn,
    HouseholdMemberOut,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/households", tags=["households"])


def _hash_code(code: str) -> str:
    return hashlib.sha256(code.encode()).hexdigest()


# ---------------------------------------------------------------------------
# List members
# ---------------------------------------------------------------------------


@router.get("/members", response_model=list[HouseholdMemberOut])
def list_members(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[HouseholdMemberOut]:
    members = session.scalars(
        select(HouseholdMember).where(
            HouseholdMember.household_id == uuid.UUID(user.household_id)
        )
    ).all()
    return [HouseholdMemberOut.model_validate(m) for m in members]


# ---------------------------------------------------------------------------
# Co-owner invite (2-step: patient/co_owner creates, target accepts)
# ---------------------------------------------------------------------------


@router.post("/invite/co-owner", status_code=status.HTTP_201_CREATED)
def invite_co_owner(
    body: CoOwnerInviteIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_roles("patient", "co_owner")),
) -> dict:
    """Generate a 6-digit one-time code for a specific user to become co-owner."""
    # Ensure there is not already a co_owner in this household
    existing = session.scalar(
        select(HouseholdMember).where(
            HouseholdMember.household_id == uuid.UUID(user.household_id),
            HouseholdMember.role == "co_owner",
        )
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Household already has a co-owner",
        )

    code = f"{secrets.randbelow(1_000_000):06d}"
    expires_at = datetime.now(tz=timezone.utc) + timedelta(
        minutes=settings.invite_code_ttl_minutes
    )
    invite = HouseholdInvite(
        household_id=uuid.UUID(user.household_id),
        invitee_user_id=body.invitee_user_id,
        role="co_owner",
        code_hash=_hash_code(code),
        expires_at=expires_at,
        created_by=uuid.UUID(user.user_id),
    )
    session.add(invite)
    session.commit()

    logger.info("co_owner_invite_created", extra={
        "invite_id": str(invite.id),
        "invitee": str(body.invitee_user_id),
        "household": user.household_id,
    })
    return {"invite_id": str(invite.id), "code": code, "expires_at": expires_at.isoformat()}


@router.post("/invite/accept", response_model=HouseholdMemberOut)
def accept_co_owner_invite(
    body: CoOwnerAcceptIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> HouseholdMemberOut:
    """Accept a co-owner invite using the 6-digit code."""
    code_hash = _hash_code(body.code)
    now = datetime.now(tz=timezone.utc)

    invite = session.scalar(
        select(HouseholdInvite).where(
            HouseholdInvite.code_hash == code_hash,
            HouseholdInvite.role == "co_owner",
            HouseholdInvite.used_at.is_(None),
            HouseholdInvite.expires_at > now,
        )
    )
    if invite is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired code")
    if invite.invitee_user_id and invite.invitee_user_id != uuid.UUID(user.user_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Code not issued for this user")

    # Mark invite used
    invite.used_at = now

    # Add member
    member = HouseholdMember(
        household_id=invite.household_id,
        user_id=uuid.UUID(user.user_id),
        role="co_owner",
        invited_by=invite.created_by,
    )
    session.add(member)
    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="co_owner_joined",
            target_table="household_members",
            target_id=member.id,
            household_id=invite.household_id,
        )
    )
    session.commit()
    return HouseholdMemberOut.model_validate(member)


# ---------------------------------------------------------------------------
# Caregiver invite (open code — any authenticated user can join)
# ---------------------------------------------------------------------------


@router.post("/caregiver-invite", response_model=CaregiverInviteOut, status_code=status.HTTP_201_CREATED)
def create_caregiver_invite(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_roles("patient", "co_owner")),
) -> CaregiverInviteOut:
    """Create an open caregiver invite code (no target user)."""
    code = f"{secrets.randbelow(1_000_000):06d}"
    ttl = settings.invite_code_ttl_minutes
    expires_at = datetime.now(tz=timezone.utc) + timedelta(minutes=ttl)
    invite = HouseholdInvite(
        household_id=uuid.UUID(user.household_id),
        invitee_user_id=None,
        role="caregiver",
        code_hash=_hash_code(code),
        expires_at=expires_at,
        created_by=uuid.UUID(user.user_id),
    )
    session.add(invite)
    session.commit()
    return CaregiverInviteOut(
        invite_id=invite.id,
        code=code,
        expires_in_minutes=ttl,
    )


@router.post("/join", response_model=HouseholdMemberOut, status_code=status.HTTP_201_CREATED)
def join_as_caregiver(
    body: CaregiverJoinIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> HouseholdMemberOut:
    """Join a household as caregiver using the 6-digit code."""
    code_hash = _hash_code(body.code)
    now = datetime.now(tz=timezone.utc)

    invite = session.scalar(
        select(HouseholdInvite).where(
            HouseholdInvite.household_id == body.household_id,
            HouseholdInvite.code_hash == code_hash,
            HouseholdInvite.role == "caregiver",
            HouseholdInvite.used_at.is_(None),
            HouseholdInvite.expires_at > now,
        )
    )
    if invite is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired code")

    # Prevent double-join
    already = session.scalar(
        select(HouseholdMember).where(
            HouseholdMember.household_id == body.household_id,
            HouseholdMember.user_id == uuid.UUID(user.user_id),
        )
    )
    if already:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Already a member of this household")

    invite.used_at = now
    member = HouseholdMember(
        household_id=body.household_id,
        user_id=uuid.UUID(user.user_id),
        role="caregiver",
        invited_by=invite.created_by,
    )
    session.add(member)
    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="caregiver_joined",
            target_table="household_members",
            target_id=member.id,
            household_id=body.household_id,
        )
    )
    session.commit()
    return HouseholdMemberOut.model_validate(member)
