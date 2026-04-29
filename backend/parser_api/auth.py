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
    apple_user_id: str | None = None,
    google_user_id: str | None = None,
    ttl_seconds: int | None = None,
) -> tuple[str, int]:
    """Create a JWT token. Called after a provider verification flow
    (Apple or Google). Returns (token, expires_in_seconds). Provider IDs
    are metadata only — pass whichever is relevant.
    """
    ttl = ttl_seconds if ttl_seconds is not None else settings.jwt_ttl_seconds
    payload: dict = {
        "household_id": household_id,
        "user_id": user_id,
        "exp": datetime.now(tz=timezone.utc) + timedelta(seconds=ttl),
    }
    if apple_user_id is not None:
        payload["apple_user_id"] = apple_user_id
    if google_user_id is not None:
        payload["google_user_id"] = google_user_id
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
        # Provider id is metadata only — Apple sets apple_user_id, Google sets
        # google_user_id; either is optional for authorization purposes.
        apple_user_id = payload.get("apple_user_id")

        if not household_id or not user_id:
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
