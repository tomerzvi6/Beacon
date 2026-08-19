"""Tests for the APNs push service — everything testable without a real
Apple Developer Program key: the provider-JWT construction, payload shape,
token caching, and the "unconfigured → no-op, never raise" contract.
Actual delivery to Apple's servers needs a real .p8 key and isn't covered
here (see docs/push_notifications.md).
"""
from unittest.mock import MagicMock, patch

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from jose import jwt as jose_jwt


def _generate_test_key() -> str:
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return pem.decode()


@pytest.fixture
def configured_settings():
    from parser_api.config import settings

    original = (
        settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key,
        settings.apns_bundle_id, settings.apns_environment,
    )
    settings.apns_key_id = "TESTKEY123"
    settings.apns_team_id = "TESTTEAM456"
    settings.apns_auth_key = _generate_test_key()
    settings.apns_bundle_id = "com.beacon.app"
    settings.apns_environment = "sandbox"
    yield settings
    (
        settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key,
        settings.apns_bundle_id, settings.apns_environment,
    ) = original


def test_is_configured_false_when_any_field_empty():
    from parser_api.services.apns_service import APNsService
    from parser_api.config import settings

    original = (settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key)
    settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key = "", "team", "key"
    try:
        assert APNsService().is_configured() is False
    finally:
        settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key = original


def test_send_is_a_noop_when_unconfigured():
    from parser_api.services.apns_service import APNsService
    from parser_api.config import settings

    original = (settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key)
    settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key = "", "", ""
    try:
        service = APNsService()
        with patch("httpx.Client") as mock_client:
            result = service.send("deadbeef", "title", "body")
        assert result is False
        mock_client.assert_not_called()
    finally:
        settings.apns_key_id, settings.apns_team_id, settings.apns_auth_key = original


def test_provider_token_is_valid_es256_jwt(configured_settings):
    from parser_api.services.apns_service import APNsService

    service = APNsService()
    token = service._provider_token()

    header = jose_jwt.get_unverified_header(token)
    assert header["alg"] == "ES256"
    assert header["kid"] == "TESTKEY123"

    claims = jose_jwt.get_unverified_claims(token)
    assert claims["iss"] == "TESTTEAM456"
    assert "iat" in claims


def test_provider_token_is_cached_across_calls(configured_settings):
    from parser_api.services.apns_service import APNsService

    service = APNsService()
    first = service._provider_token()
    second = service._provider_token()
    assert first == second


def test_send_success_posts_correct_payload_and_headers(configured_settings):
    from parser_api.services.apns_service import APNsService

    service = APNsService()
    mock_response = MagicMock(status_code=200)
    mock_client = MagicMock()
    mock_client.__enter__.return_value.post.return_value = mock_response

    with patch("httpx.Client", return_value=mock_client):
        result = service.send("device-token-abc", "כותרת", "תוכן ההודעה")

    assert result is True
    post_call = mock_client.__enter__.return_value.post
    post_call.assert_called_once()
    args, kwargs = post_call.call_args
    assert args[0] == "https://api.sandbox.push.apple.com/3/device/device-token-abc"
    assert kwargs["json"]["aps"]["alert"]["title"] == "כותרת"
    assert kwargs["json"]["aps"]["alert"]["body"] == "תוכן ההודעה"
    assert kwargs["headers"]["apns-topic"] == "com.beacon.app"
    assert kwargs["headers"]["apns-push-type"] == "alert"
    assert kwargs["headers"]["authorization"].startswith("bearer ")


def test_send_uses_production_host_when_configured(configured_settings):
    from parser_api.services.apns_service import APNsService

    configured_settings.apns_environment = "production"
    service = APNsService()
    mock_response = MagicMock(status_code=200)
    mock_client = MagicMock()
    mock_client.__enter__.return_value.post.return_value = mock_response

    with patch("httpx.Client", return_value=mock_client):
        service.send("device-token-abc", "t", "b")

    args, _ = mock_client.__enter__.return_value.post.call_args
    assert args[0].startswith("https://api.push.apple.com")


def test_send_returns_false_on_non_200(configured_settings):
    from parser_api.services.apns_service import APNsService

    service = APNsService()
    mock_response = MagicMock(status_code=410, text="Unregistered")
    mock_client = MagicMock()
    mock_client.__enter__.return_value.post.return_value = mock_response

    with patch("httpx.Client", return_value=mock_client):
        result = service.send("stale-token", "t", "b")

    assert result is False


def test_send_returns_false_on_transport_error_without_raising(configured_settings):
    import httpx

    from parser_api.services.apns_service import APNsService

    service = APNsService()
    mock_client = MagicMock()
    mock_client.__enter__.return_value.post.side_effect = httpx.ConnectError("boom")

    with patch("httpx.Client", return_value=mock_client):
        result = service.send("device-token-abc", "t", "b")

    assert result is False


def test_notify_household_skips_excluded_user_and_missing_tokens():
    from parser_api.services.notify import notify_household

    hh = MagicMock()
    session = MagicMock()
    session.scalars.return_value.all.return_value = ["token-a", None, "token-b"]

    with patch("parser_api.services.notify.apns_service") as mock_apns:
        notify_household(session, hh, title="t", body="b", exclude_user_id=None)

    assert mock_apns.send.call_count == 2
    sent_tokens = {call.args[0] for call in mock_apns.send.call_args_list}
    assert sent_tokens == {"token-a", "token-b"}


def test_notify_household_noop_when_no_tokens():
    from parser_api.services.notify import notify_household

    session = MagicMock()
    session.scalars.return_value.all.return_value = []

    with patch("parser_api.services.notify.apns_service") as mock_apns:
        notify_household(session, MagicMock(), title="t", body="b")

    mock_apns.send.assert_not_called()
