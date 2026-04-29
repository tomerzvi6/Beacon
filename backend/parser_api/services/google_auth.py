"""Google Sign-In ID-token verification.

Fetches Google's JWKS (cached 24h in-memory), verifies RS256 signature,
issuer, audience, expiry, and (optionally) nonce match.

Differs from apple_auth in two ways:
 * Issuer: Google accepts both 'accounts.google.com' and
   'https://accounts.google.com'.
 * Nonce: Apple's iOS client always supplies one; Google's only
   sometimes does (depends on whether `nonce:` was set on the
   GIDSignIn request). The caller passes `expected_nonce_raw=None`
   to skip the check.
"""
import hashlib
import time
from threading import Lock
from typing import Any

import httpx
from jose import jwt
from jose.exceptions import JWTError

JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
ALLOWED_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}
CACHE_TTL_SECONDS = 60 * 60 * 24


class GoogleTokenError(Exception):
    """Raised when a Google ID token fails verification."""


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


def verify_id_token(
    id_token: str,
    audience: str,
    expected_nonce_raw: str | None = None,
) -> dict[str, Any]:
    """Verify a Google Sign-In ID token. Returns the full claims dict.

    Validates RS256 signature against Google's JWKS, issuer, audience,
    and expiry. If `expected_nonce_raw` is provided, also enforces that
    sha256(expected_nonce_raw) matches the token's `nonce` claim.
    """
    try:
        header = jwt.get_unverified_header(id_token)
    except JWTError as exc:
        raise GoogleTokenError(f"Malformed token header: {exc}") from exc

    kid = header.get("kid")
    if not kid:
        raise GoogleTokenError("Token header missing 'kid'")

    jwks = _get_jwks()
    key = _find_key(jwks, kid)
    if key is None:
        # Google rotates keys — refresh once and retry
        jwks = _get_jwks(force_refresh=True)
        key = _find_key(jwks, kid)
    if key is None:
        raise GoogleTokenError(f"No JWKS key matching kid={kid}")

    try:
        # Skip jose's built-in issuer check — we do it manually below to
        # accept either of the two valid Google issuer values.
        claims = jwt.decode(
            id_token,
            key,
            algorithms=["RS256"],
            audience=audience,
        )
    except JWTError as exc:
        raise GoogleTokenError(f"Token verification failed: {exc}") from exc

    if claims.get("iss") not in ALLOWED_ISSUERS:
        raise GoogleTokenError(f"Unexpected issuer: {claims.get('iss')!r}")

    if expected_nonce_raw is not None:
        expected = hashlib.sha256(expected_nonce_raw.encode("utf-8")).hexdigest()
        if claims.get("nonce") != expected:
            raise GoogleTokenError("Nonce mismatch")

    return claims
