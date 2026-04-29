"""
Storage service — unified interface for S3 (prod) and local disk (dev).
Switch with STORAGE_BACKEND env var: 'local' | 's3' (default 'local').

For local mode, presigned upload URLs point to PUT /v1/uploads/local/{document_id}
served by the FastAPI app itself.
"""
import os
from pathlib import Path


# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

class StorageService:
    def generate_presigned_url(
        self,
        document_id: str,
        content_type: str,
        max_size_bytes: int = 26_214_400,  # 25 MB
    ) -> str:
        raise NotImplementedError

    def get_object_bytes(self, storage_uri: str) -> bytes:
        raise NotImplementedError

    def delete_object(self, storage_uri: str) -> None:
        raise NotImplementedError

    def storage_uri_for(self, document_id: str) -> str:
        raise NotImplementedError


# ---------------------------------------------------------------------------
# Local disk (dev)
# ---------------------------------------------------------------------------

class LocalDiskStorageService(StorageService):
    """
    Stores files under ./uploads/{document_id}.
    Presigned URL is a local API endpoint the client can PUT to.
    """

    def __init__(self, base_dir: str = "./uploads", base_url: str = "http://localhost:8000"):
        self._base = Path(base_dir)
        self._base.mkdir(parents=True, exist_ok=True)
        self._base_url = base_url.rstrip("/")

    def storage_uri_for(self, document_id: str) -> str:
        return f"local://{document_id}"

    def generate_presigned_url(
        self,
        document_id: str,
        content_type: str,
        max_size_bytes: int = 26_214_400,
    ) -> str:
        # The client PUTs the raw bytes to this URL; our local handler writes to disk.
        return f"{self._base_url}/v1/uploads/local/{document_id}"

    def get_object_bytes(self, storage_uri: str) -> bytes:
        document_id = storage_uri.removeprefix("local://")
        path = self._base / document_id
        if not path.exists():
            raise FileNotFoundError(f"Local upload not found: {path}")
        return path.read_bytes()

    def delete_object(self, storage_uri: str) -> None:
        document_id = storage_uri.removeprefix("local://")
        path = self._base / document_id
        if path.exists():
            path.unlink()

    def store_bytes(self, document_id: str, data: bytes) -> None:
        """Called by the local PUT endpoint to persist uploaded bytes."""
        (self._base / document_id).write_bytes(data)


# ---------------------------------------------------------------------------
# S3 (prod)
# ---------------------------------------------------------------------------

class S3StorageService(StorageService):
    def __init__(self):
        import boto3
        from parser_api.config import settings
        self._s3 = boto3.client("s3", region_name=settings.aws_region)
        self._bucket = settings.s3_upload_bucket

    def storage_uri_for(self, document_id: str) -> str:
        return f"s3://{self._bucket}/uploads/{document_id}"

    def generate_presigned_url(
        self,
        document_id: str,
        content_type: str,
        max_size_bytes: int = 26_214_400,
    ) -> str:
        key = f"uploads/{document_id}"
        return self._s3.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self._bucket,
                "Key": key,
                "ContentType": content_type,
                "ServerSideEncryption": "aws:kms",
                # Content-length enforcement via conditions
                "ContentLengthRange": (1, max_size_bytes),
            },
            ExpiresIn=300,
        )

    def get_object_bytes(self, storage_uri: str) -> bytes:
        parts = storage_uri.replace("s3://", "").split("/", 1)
        key = parts[1] if len(parts) > 1 else parts[0]
        resp = self._s3.get_object(Bucket=self._bucket, Key=key)
        return resp["Body"].read()

    def delete_object(self, storage_uri: str) -> None:
        parts = storage_uri.replace("s3://", "").split("/", 1)
        key = parts[1] if len(parts) > 1 else parts[0]
        self._s3.delete_object(Bucket=self._bucket, Key=key)


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

def get_storage_service() -> StorageService:
    from parser_api.config import settings
    if settings.storage_backend == "s3":
        return S3StorageService()
    return LocalDiskStorageService(
        base_dir=settings.local_upload_dir,
        base_url=settings.local_api_base_url,
    )
