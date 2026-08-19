import os
import secrets
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings


def _default_jwt_signing_key() -> str:
    """No fixed fallback here on purpose: a hardcoded default (e.g.
    'dev-secret') would let anyone forge a valid JWT against any deployment
    that forgets to set JWT_SIGNING_KEY, whether or not ENVIRONMENT was also
    set correctly. A random per-process key is safe-by-default instead —
    the only cost is that every restart invalidates existing sessions until
    a real key is configured, which is a loud, harmless signal rather than
    a silent hole.
    """
    return os.environ.get("JWT_SIGNING_KEY") or secrets.token_hex(32)


class Settings(BaseSettings):
    # Database
    database_url: str = Field(default_factory=lambda: os.environ["DATABASE_URL"])

    # Anthropic
    anthropic_api_key: str = Field(default_factory=lambda: os.environ["ANTHROPIC_API_KEY"])

    # AWS S3
    aws_region: str = Field(default="eu-central-1")
    s3_upload_bucket: str = Field(default_factory=lambda: os.environ.get("S3_UPLOAD_BUCKET", "beacon-uploads-dev"))

    # Deployment environment — gates several security checks (JWT key
    # default, Google-nonce enforcement, etc.). Set ENVIRONMENT=production
    # in real deployments.
    environment: Literal["development", "staging", "production"] = Field(default="development")

    # Auth
    jwt_signing_key: str = Field(default_factory=_default_jwt_signing_key)
    jwt_algorithm: Literal["HS256"] = "HS256"
    jwt_ttl_seconds: int = Field(default=60 * 60 * 24 * 30)  # 30 days
    apple_bundle_id: str = Field(default="com.beacon.app")
    # iOS OAuth 2.0 client ID from Google Cloud Console.
    # If empty, /v1/auth/google returns 503 (auth provider not configured).
    google_client_id: str = Field(default="")
    # Local-only escape hatch for testing the Google sign-in route without a
    # client-supplied nonce. Default-on in development so simulator/device
    # QA does not get blocked by GoogleSignIn's nonce limitation.
    # Ignored outside development.
    allow_unsigned_google_nonce: bool = Field(default=True)

    # OCR mode
    ocr_mode: Literal["textract", "tesseract"] = Field(default="tesseract")

    # Storage
    storage_backend: Literal["local", "s3"] = Field(default="local")
    local_upload_dir: str = Field(default="./uploads")
    local_api_base_url: str = Field(default="http://localhost:8000")

    # Invites
    invite_code_ttl_minutes: int = Field(default=10080)  # 7 days

    # Chief Agent (Phase 9.5)
    chief_agent_hour: int = Field(default=11)
    embedding_provider: Literal["voyage", "openai"] = Field(default="voyage")
    embedding_model: str = Field(default="voyage-2")
    voyage_api_key: str = Field(default="")
    chief_brief_max_drafts: int = Field(default=50)

    # Remote push (APNs) — Phase 9.6. Empty by default: sending is a no-op
    # (logged, not an error) until these are set. Getting real values
    # requires an Apple Developer Program membership — see
    # docs/push_notifications.md for exactly what to generate and paste in.
    apns_key_id: str = Field(default="")
    apns_team_id: str = Field(default="")
    # Contents of the .p8 Auth Key file downloaded from the Apple Developer
    # portal (Certificates, Identifiers & Profiles → Keys), PEM text
    # including the BEGIN/END lines. Never commit this — set it as a
    # deployment secret.
    apns_auth_key: str = Field(default="")
    apns_bundle_id: str = Field(default_factory=lambda: os.environ.get("APNS_BUNDLE_ID", "com.beacon.app"))
    # "sandbox" for Xcode/TestFlight builds, "production" for App Store builds.
    apns_environment: Literal["sandbox", "production"] = Field(default="sandbox")

    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
