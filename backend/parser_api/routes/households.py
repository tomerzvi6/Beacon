"""Household membership: co-owner invite (2-step) and caregiver invite (open code)."""
import hashlib
import logging
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload, create_token
from parser_api.config import settings
from parser_api.dependencies import get_session, get_user_context, require_roles
from parser_api.middleware import limiter
from shared.models import AuditLog, HouseholdInvite, HouseholdMember, User
from shared.schemas import (
    CaregiverInviteOut,
    CoOwnerAcceptIn,
    CoOwnerInviteIn,
    HouseholdMemberOut,
    RedeemInviteIn,
    RedeemInviteOut,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/households", tags=["households"])


def _hash_code(code: str) -> str:
    return hashlib.sha256(code.encode()).hexdigest()


def _issue_unique_code(session: Session) -> tuple[str, str]:
    """Return (plaintext code, hash) that no *live* invite is already using.

    A code has to be redeemable on its own — the joiner never sends a
    household id — so a collision between two open invites would send
    someone into the wrong family. Codes are only 6 digits, so we check
    against outstanding invites rather than trusting randomness.
    """
    now = datetime.now(tz=timezone.utc)
    for _ in range(10):
        code = f"{secrets.randbelow(1_000_000):06d}"
        code_hash = _hash_code(code)
        clash = session.scalar(
            select(HouseholdInvite).where(
                HouseholdInvite.code_hash == code_hash,
                HouseholdInvite.used_at.is_(None),
                HouseholdInvite.expires_at > now,
            )
        )
        if clash is None:
            return code, code_hash
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Could not allocate an invite code, please retry",
    )


# ---------------------------------------------------------------------------
# List members
# ---------------------------------------------------------------------------


@router.get("/members", response_model=list[HouseholdMemberOut])
def list_members(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[HouseholdMemberOut]:
    rows = session.execute(
        select(HouseholdMember, User.display_name).join(User, User.id == HouseholdMember.user_id).where(
            HouseholdMember.household_id == uuid.UUID(user.household_id)
        )
    ).all()
    return [
        HouseholdMemberOut(
            id=member.id,
            user_id=member.user_id,
            household_id=member.household_id,
            role=member.role,
            joined_at=member.joined_at,
            display_name=display_name,
        )
        for member, display_name in rows
    ]


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

    code, code_hash = _issue_unique_code(session)
    expires_at = datetime.now(tz=timezone.utc) + timedelta(
        minutes=settings.invite_code_ttl_minutes
    )
    invite = HouseholdInvite(
        household_id=uuid.UUID(user.household_id),
        invitee_user_id=body.invitee_user_id,
        role="co_owner",
        code_hash=code_hash,
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


@router.post("/invite/accept", response_model=HouseholdMemberOut, deprecated=True)
@limiter.limit("10/hour")
def accept_co_owner_invite(
    request: Request,
    body: CoOwnerAcceptIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> HouseholdMemberOut:
    """Deprecated — use POST /v1/households/join, which handles both roles
    and returns a refreshed token. Kept so older builds keep working.
    """
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
    code, code_hash = _issue_unique_code(session)
    ttl = settings.invite_code_ttl_minutes
    expires_at = datetime.now(tz=timezone.utc) + timedelta(minutes=ttl)
    invite = HouseholdInvite(
        household_id=uuid.UUID(user.household_id),
        invitee_user_id=None,
        role="caregiver",
        code_hash=code_hash,
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


@router.post("/join", response_model=RedeemInviteOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/hour")
def redeem_invite(
    request: Request,
    body: RedeemInviteIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> RedeemInviteOut:
    """Join a household with a 6-digit code — the only join path the app uses.

    The code carries everything: which household, and which role the joiner
    gets. Deliberately rate-limited, because a code that resolves on its own
    is only 6 digits wide and would otherwise be guessable.
    """
    code_hash = _hash_code(body.code)
    now = datetime.now(tz=timezone.utc)

    invite = session.scalar(
        select(HouseholdInvite).where(
            HouseholdInvite.code_hash == code_hash,
            HouseholdInvite.used_at.is_(None),
            HouseholdInvite.expires_at > now,
        )
    )
    if invite is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="קוד לא תקין או שפג תוקפו")

    # Targeted invites (co-owner aimed at a specific user) stay targeted.
    if invite.invitee_user_id and invite.invitee_user_id != uuid.UUID(user.user_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="הקוד הונפק עבור משתמש אחר")

    already = session.scalar(
        select(HouseholdMember).where(
            HouseholdMember.household_id == invite.household_id,
            HouseholdMember.user_id == uuid.UUID(user.user_id),
        )
    )
    if already:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="כבר חבר/ה במשפחה הזו")

    invite.used_at = now
    # id/joined_at are set here rather than left to the column defaults so the
    # response can be built without a flush round-trip (same reasoning as the
    # Apple sign-up path in routes/auth.py).
    member = HouseholdMember(
        id=uuid.uuid4(),
        household_id=invite.household_id,
        user_id=uuid.UUID(user.user_id),
        role=invite.role,
        invited_by=invite.created_by,
        joined_at=now,
    )
    session.add(member)

    # Point the user at the household they just joined. `users.household_id`
    # is what every future sign-in reads to build the JWT, so without this
    # the next login would drop them back into their own empty household.
    joining_user = session.scalar(select(User).where(User.id == uuid.UUID(user.user_id)))
    if joining_user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    joining_user.household_id = invite.household_id

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action=f"{invite.role}_joined",
            target_table="household_members",
            target_id=member.id,
            household_id=invite.household_id,
        )
    )
    session.commit()

    token, ttl = create_token(
        household_id=str(invite.household_id),
        user_id=user.user_id,
    )
    return RedeemInviteOut(
        member=HouseholdMemberOut.model_validate(member),
        access_token=token,
        expires_in_seconds=ttl,
    )
