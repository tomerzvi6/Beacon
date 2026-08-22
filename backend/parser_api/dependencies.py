"""FastAPI dependency injection."""
import uuid
from typing import Generator

from fastapi import Depends, HTTPException, status
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload, verify_token
from parser_api.config import settings


_engine = None


def get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine(settings.database_url, pool_pre_ping=True)
    return _engine


def get_session(
    token: TokenPayload = Depends(verify_token),
) -> Generator[Session, None, None]:
    """Get DB session with RLS context set to user's household.

    Also re-checks that the caller still has a household_members row —
    a JWT stays valid for its full TTL even after the patient/co_owner
    revokes the caregiver, so without this check a revoked caregiver would
    keep full access until the token naturally expired.
    """
    engine = get_engine()
    with Session(engine) as session:
        _set_rls_and_verify_membership(session, token)
        yield session


def _set_rls_and_verify_membership(session: Session, token: TokenPayload) -> None:
    from shared.db import set_rls_household
    from shared.models import HouseholdMember

    set_rls_household(session, token.household_id)
    member = session.scalar(
        select(HouseholdMember).where(
            HouseholdMember.household_id == uuid.UUID(token.household_id),
            HouseholdMember.user_id == uuid.UUID(token.user_id),
        )
    )
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Household membership not found — access may have been revoked",
        )


def get_session_no_auth() -> Generator[Session, None, None]:
    """Session WITHOUT RLS context — for endpoints that bootstrap auth (no
    household yet, e.g. POST /v1/auth/apple). Relies on parser_api_role having
    row_security=off; production must keep that role attribute or substitute a
    SECURITY DEFINER lookup.
    """
    engine = get_engine()
    with Session(engine) as session:
        yield session


def get_user_context(token: TokenPayload = Depends(verify_token)) -> TokenPayload:
    """Extract user context from JWT."""
    return token


def require_roles(*allowed: str):
    """
    Dependency factory: raises 403 if the caller's household_member role is not
    in `allowed`. Usage: Depends(require_roles("patient", "co_owner"))
    """
    def _check(
        token: TokenPayload = Depends(verify_token),
        session: Session = Depends(get_session),
    ) -> TokenPayload:
        from shared.models import HouseholdMember

        member = session.scalar(
            select(HouseholdMember).where(
                HouseholdMember.household_id == uuid.UUID(token.household_id),
                HouseholdMember.user_id == uuid.UUID(token.user_id),
            )
        )
        if member is None or member.role not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Role '{getattr(member, 'role', None)}' not permitted; "
                       f"required: {list(allowed)}",
            )
        return token

    return _check


def require_module_access(module: str, min_level: int):
    """
    Dependency factory enforcing the per-module AccessLevel a patient/co_owner
    configured for a caregiver (schedule|tasks|medications|medicalVault|feed,
    0=none/1=read/2=readWrite — mirrors AppModule/AccessLevel on iOS).

    patient/co_owner always pass (full access by definition). A caregiver
    with no explicit entry for `module` defaults to read (1), matching
    MemberRole.defaultMember on the client. Usage:
    Depends(require_module_access("medications", 2))  # write endpoint
    """
    def _check(
        token: TokenPayload = Depends(verify_token),
        session: Session = Depends(get_session),
    ) -> TokenPayload:
        from shared.models import HouseholdMember

        member = session.scalar(
            select(HouseholdMember).where(
                HouseholdMember.household_id == uuid.UUID(token.household_id),
                HouseholdMember.user_id == uuid.UUID(token.user_id),
            )
        )
        if member is None:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Membership not found")
        if member.role in ("patient", "co_owner"):
            return token
        level = (member.permissions or {}).get(module, 1)
        if level < min_level:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access level {level} for '{module}' below required {min_level}",
            )
        return token

    return _check
