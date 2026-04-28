"""FastAPI dependency injection."""
from typing import Generator

from fastapi import Depends
from sqlalchemy import create_engine
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
