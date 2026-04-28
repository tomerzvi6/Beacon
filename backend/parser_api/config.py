import os
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Database
    database_url: str = Field(default_factory=lambda: os.environ["DATABASE_URL"])

    # Anthropic
    anthropic_api_key: str = Field(default_factory=lambda: os.environ["ANTHROPIC_API_KEY"])

    # AWS S3
    aws_region: str = Field(default="eu-central-1")
    s3_upload_bucket: str = Field(default_factory=lambda: os.environ.get("S3_UPLOAD_BUCKET", "beacon-uploads-dev"))

    # Auth
    jwt_signing_key: str = Field(default_factory=lambda: os.environ.get("JWT_SIGNING_KEY", "dev-secret"))
    jwt_algorithm: Literal["HS256"] = "HS256"
    jwt_expires_seconds: int = 3600

    # OCR mode
    ocr_mode: Literal["textract", "tesseract"] = Field(default="tesseract")

    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
