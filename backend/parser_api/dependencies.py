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
    """Get DB session with RLS context set to user's household."""
    from shared.db import set_rls_household

    engine = get_engine()
    with Session(engine) as session:
        set_rls_household(session, token.household_id)
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
