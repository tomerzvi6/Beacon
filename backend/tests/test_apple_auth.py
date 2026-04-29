"""Tests for Apple identity-token verification + POST /v1/auth/apple."""
import hashlib
import time
import uuid
from unittest.mock import MagicMock, patch

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import HTTPException
from jose import jwk, jwt

from parser_api.services import apple_auth
from parser_api.services.apple_auth import AppleTokenError, verify_identity_token


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
    pub_jwk["kid"] = "test-kid"
    pub_jwk["alg"] = "RS256"
    pub_jwk["use"] = "sig"
    return {"priv_pem": priv_pem, "pub_jwk": pub_jwk}


@pytest.fixture
def patched_jwks(keypair):
    apple_auth.reset_cache_for_tests()
    with patch.object(
        apple_auth,
        "_fetch_jwks",
        return_value={"keys": [keypair["pub_jwk"]]},
    ):
        yield
    apple_auth.reset_cache_for_tests()


def _make_token(keypair, claims, kid="test-kid"):
    return jwt.encode(
        claims,
        keypair["priv_pem"],
        algorithm="RS256",
        headers={"kid": kid},
    )


def _valid_claims(nonce_raw="raw-nonce-xyz", aud="com.beacon.app", sub="apple-user-12345"):
    return {
        "iss": "https://appleid.apple.com",
        "aud": aud,
        "sub": sub,
        "nonce": hashlib.sha256(nonce_raw.encode()).hexdigest(),
        "exp": int(time.time()) + 3600,
        "iat": int(time.time()),
    }


# ---------------------------------------------------------------------------
# verify_identity_token
# ---------------------------------------------------------------------------


def test_verify_happy_path(keypair, patched_jwks):
    nonce = "fresh-nonce-abc"
    token = _make_token(keypair, _valid_claims(nonce_raw=nonce))
    claims = verify_identity_token(token, nonce_raw=nonce, audience="com.beacon.app")
    assert claims["sub"] == "apple-user-12345"
    assert claims["iss"] == "https://appleid.apple.com"


def test_verify_rejects_nonce_mismatch(keypair, patched_jwks):
    token = _make_token(keypair, _valid_claims(nonce_raw="real-nonce"))
    with pytest.raises(AppleTokenError, match="Nonce"):
        verify_identity_token(token, nonce_raw="wrong-nonce", audience="com.beacon.app")


def test_verify_rejects_wrong_audience(keypair, patched_jwks):
    nonce = "n1"
    token = _make_token(keypair, _valid_claims(nonce_raw=nonce, aud="com.attacker.app"))
    with pytest.raises(AppleTokenError):
        verify_identity_token(token, nonce_raw=nonce, audience="com.beacon.app")


def test_verify_rejects_expired(keypair, patched_jwks):
    nonce = "n1"
    claims = _valid_claims(nonce_raw=nonce)
    claims["exp"] = int(time.time()) - 60
    token = _make_token(keypair, claims)
    with pytest.raises(AppleTokenError):
        verify_identity_token(token, nonce_raw=nonce, audience="com.beacon.app")


def test_verify_rejects_unknown_kid(keypair, patched_jwks):
    nonce = "n1"
    token = _make_token(keypair, _valid_claims(nonce_raw=nonce), kid="rotated-kid-not-in-jwks")
    with pytest.raises(AppleTokenError, match="No JWKS key"):
        verify_identity_token(token, nonce_raw=nonce, audience="com.beacon.app")


def test_verify_rejects_malformed_token(patched_jwks):
    with pytest.raises(AppleTokenError):
        verify_identity_token("not.a.real.jwt", nonce_raw="x", audience="com.beacon.app")


# ---------------------------------------------------------------------------
# POST /v1/auth/apple route
# ---------------------------------------------------------------------------


def _new_user_session():
    """First scalar (User lookup) returns None; second (HouseholdMember post-
    create) returns a member with role=patient.
    """
    session = MagicMock()
    member = MagicMock()
    member.role = "patient"
    session.scalar.side_effect = [None, member]
    return session


def _existing_user_session(role="co_owner"):
    user = MagicMock()
    user.id = uuid.uuid4()
    user.household_id = uuid.uuid4()
    user.apple_user_id = "apple-user-12345"
    user.display_name = "Existing Name"

    member = MagicMock()
    member.role = role

    session = MagicMock()
    session.scalar.side_effect = [user, member]
    return session, user


def test_route_creates_household_for_new_user(keypair, patched_jwks):
    from parser_api.routes.auth import exchange_apple_token
    from shared.schemas import AppleAuthIn, AppleFullName

    nonce = "first-nonce"
    token_jwt = _make_token(keypair, _valid_claims(nonce_raw=nonce))
    body = AppleAuthIn(
        identity_token=token_jwt,
        nonce=nonce,
        full_name=AppleFullName(given_name="Tomer", family_name="Levi"),
    )
    session = _new_user_session()

    response = exchange_apple_token(body, session=session)

    assert response.token_type == "bearer"
    assert response.access_token  # non-empty JWT
    assert response.user.role == "patient"
    assert response.user.full_name == "Tomer Levi"
    assert response.expires_in_seconds > 0
    # Household + User + HouseholdMember + AuditLog
    assert session.add.call_count == 4
    session.commit.assert_called()


def test_route_returns_existing_user_idempotently(keypair, patched_jwks):
    from parser_api.routes.auth import exchange_apple_token
    from shared.schemas import AppleAuthIn

    nonce = "second-nonce"
    token_jwt = _make_token(keypair, _valid_claims(nonce_raw=nonce))
    body = AppleAuthIn(identity_token=token_jwt, nonce=nonce, full_name=None)
    session, existing = _existing_user_session(role="co_owner")

    response = exchange_apple_token(body, session=session)

    assert response.user.id == existing.id
    assert response.user.household_id == existing.household_id
    assert response.user.role == "co_owner"
    assert response.user.full_name == "Existing Name"
    # Only an audit log row added — no Household / User / HouseholdMember inserts
    assert session.add.call_count == 1


def test_route_ignores_full_name_for_existing_user(keypair, patched_jwks):
    from parser_api.routes.auth import exchange_apple_token
    from shared.schemas import AppleAuthIn, AppleFullName

    nonce = "n"
    token_jwt = _make_token(keypair, _valid_claims(nonce_raw=nonce))
    body = AppleAuthIn(
        identity_token=token_jwt,
        nonce=nonce,
        full_name=AppleFullName(given_name="Attacker", family_name="Replaced"),
    )
    session, existing = _existing_user_session()

    response = exchange_apple_token(body, session=session)

    assert response.user.full_name == "Existing Name"  # unchanged


def test_route_rejects_invalid_token(patched_jwks):
    from parser_api.routes.auth import exchange_apple_token
    from shared.schemas import AppleAuthIn

    body = AppleAuthIn(identity_token="not.a.real.jwt", nonce="x", full_name=None)
    session = MagicMock()

    with pytest.raises(HTTPException) as exc:
        exchange_apple_token(body, session=session)
    assert exc.value.status_code == 401


def test_route_rejects_nonce_mismatch(keypair, patched_jwks):
    from parser_api.routes.auth import exchange_apple_token
    from shared.schemas import AppleAuthIn

    token_jwt = _make_token(keypair, _valid_claims(nonce_raw="server-saw"))
    body = AppleAuthIn(identity_token=token_jwt, nonce="client-sent-different", full_name=None)
    session = MagicMock()

    with pytest.raises(HTTPException) as exc:
        exchange_apple_token(body, session=session)
    assert exc.value.status_code == 401


def test_route_returns_jwt_we_can_verify(keypair, patched_jwks):
    """End-to-end: response token must be decodable with our signing key."""
    from parser_api.auth import settings as parser_settings
    from parser_api.routes.auth import exchange_apple_token
    from shared.schemas import AppleAuthIn

    nonce = "round-trip"
    token_jwt = _make_token(keypair, _valid_claims(nonce_raw=nonce, sub="apple-roundtrip"))
    body = AppleAuthIn(identity_token=token_jwt, nonce=nonce, full_name=None)
    session = _new_user_session()

    response = exchange_apple_token(body, session=session)
    decoded = jwt.decode(
        response.access_token,
        parser_settings.jwt_signing_key,
        algorithms=[parser_settings.jwt_algorithm],
    )
    assert decoded["apple_user_id"] == "apple-roundtrip"
    assert decoded["household_id"] == str(response.user.household_id)
    assert decoded["user_id"] == str(response.user.id)
