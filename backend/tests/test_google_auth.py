"""Tests for Google ID-token verification + POST /v1/auth/google."""
import hashlib
import time
import uuid
from unittest.mock import MagicMock, patch

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException
from jose import jwk, jwt

from parser_api.services import google_auth
from parser_api.services.google_auth import GoogleTokenError, verify_id_token


CLIENT_ID = "1234567890-abc.apps.googleusercontent.com"


# ---------------------------------------------------------------------------
# Keypair + JWKS fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def keypair():
    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    priv_pem = priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    pub_pem = priv.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()
    pub_jwk = jwk.construct(pub_pem, algorithm="RS256").to_dict()
    pub_jwk["kid"] = "google-test-kid"
    pub_jwk["alg"] = "RS256"
    pub_jwk["use"] = "sig"
    return {"priv_pem": priv_pem, "pub_jwk": pub_jwk}


@pytest.fixture
def patched_jwks(keypair):
    google_auth.reset_cache_for_tests()
    with patch.object(
        google_auth,
        "_fetch_jwks",
        return_value={"keys": [keypair["pub_jwk"]]},
    ):
        yield
    google_auth.reset_cache_for_tests()


@pytest.fixture
def configured_client_id():
    """Force settings.google_client_id non-empty for route tests."""
    from parser_api.config import settings as parser_settings
    original = parser_settings.google_client_id
    parser_settings.google_client_id = CLIENT_ID
    yield CLIENT_ID
    parser_settings.google_client_id = original


def _make_token(keypair, claims, kid="google-test-kid"):
    return jwt.encode(
        claims,
        keypair["priv_pem"],
        algorithm="RS256",
        headers={"kid": kid},
    )


def _valid_claims(
    aud=CLIENT_ID,
    sub="google-user-987654",
    iss="https://accounts.google.com",
    nonce_raw=None,
    name="Tomer Levi",
    email="tomer@example.com",
    email_verified=True,
):
    claims = {
        "iss": iss,
        "aud": aud,
        "sub": sub,
        "exp": int(time.time()) + 3600,
        "iat": int(time.time()),
        "name": name,
        "given_name": name.split()[0] if name else None,
        "family_name": " ".join(name.split()[1:]) if name and len(name.split()) > 1 else None,
        "email": email,
        "email_verified": email_verified,
    }
    if nonce_raw is not None:
        claims["nonce"] = hashlib.sha256(nonce_raw.encode()).hexdigest()
    return claims


# ---------------------------------------------------------------------------
# verify_id_token
# ---------------------------------------------------------------------------


def test_verify_happy_path_no_nonce(keypair, patched_jwks):
    token = _make_token(keypair, _valid_claims())
    claims = verify_id_token(token, audience=CLIENT_ID)
    assert claims["sub"] == "google-user-987654"


def test_verify_accepts_alt_issuer(keypair, patched_jwks):
    token = _make_token(keypair, _valid_claims(iss="accounts.google.com"))
    claims = verify_id_token(token, audience=CLIENT_ID)
    assert claims["iss"] == "accounts.google.com"


def test_verify_rejects_wrong_issuer(keypair, patched_jwks):
    token = _make_token(keypair, _valid_claims(iss="https://attacker.example"))
    with pytest.raises(GoogleTokenError, match="issuer"):
        verify_id_token(token, audience=CLIENT_ID)


def test_verify_rejects_wrong_audience(keypair, patched_jwks):
    token = _make_token(keypair, _valid_claims(aud="other.client.id"))
    with pytest.raises(GoogleTokenError):
        verify_id_token(token, audience=CLIENT_ID)


def test_verify_rejects_expired(keypair, patched_jwks):
    claims = _valid_claims()
    claims["exp"] = int(time.time()) - 60
    token = _make_token(keypair, claims)
    with pytest.raises(GoogleTokenError):
        verify_id_token(token, audience=CLIENT_ID)


def test_verify_validates_nonce_when_provided(keypair, patched_jwks):
    nonce = "client-nonce"
    token = _make_token(keypair, _valid_claims(nonce_raw=nonce))
    claims = verify_id_token(token, audience=CLIENT_ID, expected_nonce_raw=nonce)
    assert claims["sub"] == "google-user-987654"


def test_verify_rejects_nonce_mismatch(keypair, patched_jwks):
    token = _make_token(keypair, _valid_claims(nonce_raw="server-nonce"))
    with pytest.raises(GoogleTokenError, match="Nonce"):
        verify_id_token(token, audience=CLIENT_ID, expected_nonce_raw="other-nonce")


def test_verify_skips_nonce_when_none(keypair, patched_jwks):
    """Caller passing None opts out of nonce enforcement, even if the
    token happens to carry a nonce claim — used for Google flows where
    the iOS side didn't request one."""
    token = _make_token(keypair, _valid_claims(nonce_raw="something"))
    claims = verify_id_token(token, audience=CLIENT_ID, expected_nonce_raw=None)
    assert claims["sub"] == "google-user-987654"


def test_verify_rejects_unknown_kid(keypair, patched_jwks):
    token = _make_token(keypair, _valid_claims(), kid="rotated-kid")
    with pytest.raises(GoogleTokenError, match="No JWKS key"):
        verify_id_token(token, audience=CLIENT_ID)


# ---------------------------------------------------------------------------
# POST /v1/auth/google route
# ---------------------------------------------------------------------------


def _new_user_session():
    session = MagicMock()
    member = MagicMock()
    member.role = "patient"
    session.scalar.side_effect = [None, member]
    return session


def _existing_user_session(role="caregiver"):
    user = MagicMock()
    user.id = uuid.uuid4()
    user.household_id = uuid.uuid4()
    user.google_user_id = "google-user-987654"
    user.display_name = "Existing Google User"

    member = MagicMock()
    member.role = role

    session = MagicMock()
    session.scalar.side_effect = [user, member]
    return session, user


def test_route_creates_user_for_new_google_signin(keypair, patched_jwks, configured_client_id):
    from parser_api.routes.auth import exchange_google_token
    from shared.schemas import GoogleAuthIn

    token_jwt = _make_token(keypair, _valid_claims(name="Dana Cohen"))
    body = GoogleAuthIn(id_token=token_jwt, nonce=None)
    session = _new_user_session()

    response = exchange_google_token(body, session=session)

    assert response.token_type == "bearer"
    assert response.access_token
    assert response.user.role == "patient"
    assert response.user.full_name == "Dana Cohen"
    assert response.expires_in_seconds > 0
    assert session.add.call_count == 4  # household + user + member + audit


def test_route_returns_existing_user_idempotently(keypair, patched_jwks, configured_client_id):
    from parser_api.routes.auth import exchange_google_token
    from shared.schemas import GoogleAuthIn

    token_jwt = _make_token(keypair, _valid_claims())
    body = GoogleAuthIn(id_token=token_jwt, nonce=None)
    session, existing = _existing_user_session(role="caregiver")

    response = exchange_google_token(body, session=session)

    assert response.user.id == existing.id
    assert response.user.household_id == existing.household_id
    assert response.user.role == "caregiver"
    assert response.user.full_name == "Existing Google User"
    assert session.add.call_count == 1  # audit only


def test_route_returns_503_when_client_id_unconfigured(keypair, patched_jwks):
    """Without GOOGLE_CLIENT_ID in env, the endpoint must fail closed."""
    from parser_api.config import settings as parser_settings
    from parser_api.routes.auth import exchange_google_token
    from shared.schemas import GoogleAuthIn

    original = parser_settings.google_client_id
    parser_settings.google_client_id = ""
    try:
        body = GoogleAuthIn(id_token="anything", nonce=None)
        with pytest.raises(HTTPException) as exc:
            exchange_google_token(body, session=MagicMock())
        assert exc.value.status_code == 503
    finally:
        parser_settings.google_client_id = original


def test_route_rejects_invalid_token(patched_jwks, configured_client_id):
    from parser_api.routes.auth import exchange_google_token
    from shared.schemas import GoogleAuthIn

    body = GoogleAuthIn(id_token="not.a.real.jwt", nonce=None)
    with pytest.raises(HTTPException) as exc:
        exchange_google_token(body, session=MagicMock())
    assert exc.value.status_code == 401


def test_route_rejects_nonce_mismatch_when_supplied(keypair, patched_jwks, configured_client_id):
    from parser_api.routes.auth import exchange_google_token
    from shared.schemas import GoogleAuthIn

    token_jwt = _make_token(keypair, _valid_claims(nonce_raw="server"))
    body = GoogleAuthIn(id_token=token_jwt, nonce="client-different")
    with pytest.raises(HTTPException) as exc:
        exchange_google_token(body, session=MagicMock())
    assert exc.value.status_code == 401


def test_route_returns_jwt_we_can_verify(keypair, patched_jwks, configured_client_id):
    from parser_api.auth import settings as parser_settings
    from parser_api.routes.auth import exchange_google_token
    from shared.schemas import GoogleAuthIn

    token_jwt = _make_token(keypair, _valid_claims(sub="round-trip-google"))
    body = GoogleAuthIn(id_token=token_jwt, nonce=None)
    session = _new_user_session()

    response = exchange_google_token(body, session=session)
    decoded = jwt.decode(
        response.access_token,
        parser_settings.jwt_signing_key,
        algorithms=[parser_settings.jwt_algorithm],
    )
    assert decoded["google_user_id"] == "round-trip-google"
    assert "apple_user_id" not in decoded
    assert decoded["household_id"] == str(response.user.household_id)
