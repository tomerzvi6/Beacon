"""Apple Sign-In identity-token verification.

Fetches Apple's JWKS (cached 24h in-memory), verifies RS256 signature,
issuer, audience, expiry, and nonce match.
"""
import hashlib
import time
from threading import Lock
from typing import Any

import httpx
from jose import jwt
from jose.exceptions import JWTError

JWKS_URL = "https://appleid.apple.com/auth/keys"
ISSUER = "https://appleid.apple.com"
CACHE_TTL_SECONDS = 60 * 60 * 24


class AppleTokenError(Exception):
    """Raised when an Apple identity token fails verification."""


_jwks_cache: dict[str, Any] | None = None
_jwks_cached_at: float = 0.0
_lock = Lock()


def _fetch_jwks() -> dict[str, Any]:
    resp = httpx.get(JWKS_URL, timeout=5.0)
    resp.raise_for_status()
    return resp.json()


def _get_jwks(force_refresh: bool = False) -> dict[str, Any]:
    global _jwks_cache, _jwks_cached_at
    with _lock:
        fresh = _jwks_cache is not None and (time.time() - _jwks_cached_at) < CACHE_TTL_SECONDS
        if force_refresh or not fresh:
            _jwks_cache = _fetch_jwks()
            _jwks_cached_at = time.time()
        return _jwks_cache


def _find_key(jwks: dict[str, Any], kid: str) -> dict[str, Any] | None:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key
    return None


def reset_cache_for_tests() -> None:
    """Clears JWKS cache. Test-only — never call from production code."""
    global _jwks_cache, _jwks_cached_at
    with _lock:
        _jwks_cache = None
        _jwks_cached_at = 0.0


def verify_identity_token(
    identity_token: str,
    nonce_raw: str,
    audience: str,
) -> dict[str, Any]:
    """Verify an Apple Sign-In identity token. Returns the full claims dict.

    Validates: RS256 signature against Apple's JWKS, iss, aud, exp, and that
    sha256(nonce_raw) matches the 'nonce' claim.
    """
    try:
        header = jwt.get_unverified_header(identity_token)
    except JWTError as exc:
        raise AppleTokenError(f"Malformed token header: {exc}") from exc

    kid = header.get("kid")
    if not kid:
        raise AppleTokenError("Token header missing 'kid'")

    jwks = _get_jwks()
    key = _find_key(jwks, kid)
    if key is None:
        # Apple rotated keys — refresh once and retry
        jwks = _get_jwks(force_refresh=True)
        key = _find_key(jwks, kid)
    if key is None:
        raise AppleTokenError(f"No JWKS key matching kid={kid}")

    try:
        claims = jwt.decode(
            identity_token,
            key,
            algorithms=["RS256"],
            audience=audience,
            issuer=ISSUER,
        )
    except JWTError as exc:
        raise AppleTokenError(f"Token verification failed: {exc}") from exc

    expected = hashlib.sha256(nonce_raw.encode("utf-8")).hexdigest()
    if claims.get("nonce") != expected:
        raise AppleTokenError("Nonce mismatch")

    return claims
