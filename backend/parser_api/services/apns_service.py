"""Remote push via Apple Push Notification service (APNs).

Needs three things only a paid Apple Developer Program membership can
produce: a Team ID, a Key ID, and a .p8 Auth Key downloaded from
Certificates, Identifiers & Profiles → Keys. Until `settings.apns_key_id`
etc. are set, `send()` is a logged no-op — callers never need to check
`is_configured()` themselves.
"""
import logging
import time

import httpx
from jose import jwt as jose_jwt

from parser_api.config import settings

logger = logging.getLogger(__name__)

_HOSTS = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}

# Apple allows a provider token to be reused for up to an hour and rate-limits
# how often a new one may be minted — refresh a few minutes early rather than
# cutting it as close as possible.
_TOKEN_TTL_SECONDS = 50 * 60


class APNsService:
    def __init__(self) -> None:
        self._cached_token: str | None = None
        self._cached_token_issued_at: float = 0.0

    def is_configured(self) -> bool:
        return bool(settings.apns_key_id and settings.apns_team_id and settings.apns_auth_key)

    def _provider_token(self) -> str:
        now = time.time()
        if self._cached_token and (now - self._cached_token_issued_at) < _TOKEN_TTL_SECONDS:
            return self._cached_token
        token = jose_jwt.encode(
            {"iss": settings.apns_team_id, "iat": int(now)},
            settings.apns_auth_key,
            algorithm="ES256",
            headers={"kid": settings.apns_key_id},
        )
        self._cached_token = token
        self._cached_token_issued_at = now
        return token

    def send(
        self,
        device_token: str,
        title: str,
        body: str,
        data: dict | None = None,
    ) -> bool:
        """Send one alert push. Returns True on APNs 200, False on any
        failure (unconfigured, network error, APNs rejection) — logged
        either way, never raised, so a push failure never breaks the
        request that triggered it (e.g. posting to the feed).

        Blocking, like the rest of this codebase's request handling — the
        whole app is sync SQLAlchemy with no async routes, so a blocking
        HTTP/2 call here (instead of pulling in an async test/route
        pattern that exists nowhere else in the project) is the smaller,
        more consistent change.
        """
        if not self.is_configured():
            logger.info("apns_not_configured", extra={"would_send_to": device_token[:8] + "…"})
            return False

        host = _HOSTS[settings.apns_environment]
        payload: dict = {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
        if data:
            payload.update(data)

        try:
            with httpx.Client(http2=True, timeout=10.0) as client:
                response = client.post(
                    f"{host}/3/device/{device_token}",
                    json=payload,
                    headers={
                        "authorization": f"bearer {self._provider_token()}",
                        "apns-topic": settings.apns_bundle_id,
                        "apns-push-type": "alert",
                        "apns-priority": "10",
                    },
                )
            if response.status_code == 200:
                return True
            logger.warning(
                "apns_send_failed",
                extra={"status": response.status_code, "body": response.text[:500]},
            )
            return False
        except httpx.HTTPError as exc:
            logger.warning("apns_send_error", extra={"error": str(exc)})
            return False


apns_service = APNsService()
