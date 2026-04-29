"""JWT and Sign in with Apple verification."""
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from parser_api.config import settings

security = HTTPBearer()


class TokenPayload:
    def __init__(self, household_id: str, user_id: str, apple_user_id: str | None = None):
        self.household_id = household_id
        self.user_id = user_id
        self.apple_user_id = apple_user_id


def create_token(
    household_id: str,
    user_id: str,
    apple_user_id: str,
    ttl_seconds: int | None = None,
) -> tuple[str, int]:
    """Create a JWT token. Called after Sign in with Apple verification.

    Returns (token, expires_in_seconds).
    """
    ttl = ttl_seconds if ttl_seconds is not None else settings.jwt_ttl_seconds
    payload = {
        "household_id": household_id,
        "user_id": user_id,
        "apple_user_id": apple_user_id,
        "exp": datetime.now(tz=timezone.utc) + timedelta(seconds=ttl),
    }
    token = jwt.encode(payload, settings.jwt_signing_key, algorithm=settings.jwt_algorithm)
    return token, ttl


def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)) -> TokenPayload:
    """Verify JWT and extract user context."""
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_signing_key,
            algorithms=[settings.jwt_algorithm],
        )
        household_id = payload.get("household_id")
        user_id = payload.get("user_id")
        apple_user_id = payload.get("apple_user_id")

        if not all([household_id, user_id, apple_user_id]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token payload",
            )

        return TokenPayload(household_id, user_id, apple_user_id)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
