"""Sign in with Apple → Beacon JWT exchange."""
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.auth import create_token
from parser_api.config import settings
from parser_api.dependencies import get_session_no_auth
from parser_api.services.apple_auth import AppleTokenError, verify_identity_token
from shared.models import AuditLog, Household, HouseholdMember, User
from shared.schemas import (
    AppleAuthIn,
    AppleAuthOut,
    AppleAuthUserOut,
    AppleFullName,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/auth", tags=["auth"])


def _format_full_name(fn: AppleFullName | None) -> str:
    if fn is None:
        return "משתמש"
    parts = [p.strip() for p in (fn.given_name, fn.family_name) if p and p.strip()]
    return " ".join(parts) if parts else "משתמש"


@router.post("/apple", response_model=AppleAuthOut)
def exchange_apple_token(
    body: AppleAuthIn,
    session: Session = Depends(get_session_no_auth),
) -> AppleAuthOut:
    """Verify an Apple Sign-In identity token and return a Beacon JWT.

    On first call for a given Apple user, creates a Household + User +
    HouseholdMember(role=patient). On subsequent calls, looks up the existing
    user — display_name is set only on creation; full_name in the body is
    ignored once a user exists (Apple only returns it on first sign-in anyway).
    """
    try:
        claims = verify_identity_token(
            identity_token=body.identity_token,
            nonce_raw=body.nonce,
            audience=settings.apple_bundle_id,
        )
    except AppleTokenError as exc:
        logger.warning("apple_token_rejected", extra={"reason": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Apple token verification failed: {exc}",
        )

    apple_user_id = claims.get("sub")
    if not apple_user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Apple token missing 'sub'",
        )

    user = session.scalar(select(User).where(User.apple_user_id == apple_user_id))
    is_new = user is None

    if is_new:
        # Generate IDs explicitly to avoid relying on a flush round-trip.
        household_id = uuid.uuid4()
        user_id = uuid.uuid4()
        member_id = uuid.uuid4()

        household = Household(id=household_id)
        session.add(household)

        display_name = _format_full_name(body.full_name)
        user = User(
            id=user_id,
            apple_user_id=apple_user_id,
            household_id=household_id,
            display_name=display_name,
            role="patient",  # legacy column; authoritative role lives in household_members
        )
        session.add(user)

        member = HouseholdMember(
            id=member_id,
            household_id=household_id,
            user_id=user_id,
            role="patient",
        )
        session.add(member)

        session.add(
            AuditLog(
                actor_type="parser_api",
                actor_id=str(user_id),
                action="apple_signup",
                target_table="users",
                target_id=user_id,
                household_id=household_id,
            )
        )
        session.commit()
        logger.info(
            "apple_signup",
            extra={"user_id": str(user_id), "household_id": str(household_id)},
        )

    member = session.scalar(
        select(HouseholdMember).where(
            HouseholdMember.household_id == user.household_id,
            HouseholdMember.user_id == user.id,
        )
    )
    role = member.role if member else "patient"

    if not is_new:
        session.add(
            AuditLog(
                actor_type="parser_api",
                actor_id=str(user.id),
                action="apple_signin",
                target_table="users",
                target_id=user.id,
                household_id=user.household_id,
            )
        )
        session.commit()

    token, ttl = create_token(
        household_id=str(user.household_id),
        user_id=str(user.id),
        apple_user_id=apple_user_id,
    )

    return AppleAuthOut(
        access_token=token,
        token_type="bearer",
        user=AppleAuthUserOut(
            id=user.id,
            household_id=user.household_id,
            role=role,
            full_name=user.display_name,
        ),
        expires_in_seconds=ttl,
    )
