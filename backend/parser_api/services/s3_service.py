"""AWS S3 service for document uploads."""
import boto3

from parser_api.config import settings


class S3Service:
    def __init__(self):
        self.s3_client = boto3.client("s3", region_name=settings.aws_region)
        self.bucket = settings.s3_upload_bucket

    def generate_presigned_url(self, document_id: str, content_type: str = "application/pdf") -> str:
        """Generate a presigned PUT URL for direct iOS upload to S3."""
        key = f"uploads/{document_id}"
        url = self.s3_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self.bucket,
                "Key": key,
                "ContentType": content_type,
                "ServerSideEncryption": "aws:kms",
            },
            ExpiresIn=300,  # 5 minutes
        )
        return url

    def get_object_bytes(self, storage_uri: str) -> bytes:
        """Retrieve document bytes from S3 for OCR processing."""
        # storage_uri format: s3://bucket/uploads/document_id
        parts = storage_uri.replace("s3://", "").split("/", 1)
        key = parts[1]

        response = self.s3_client.get_object(Bucket=self.bucket, Key=key)
        return response["Body"].read()

    def delete_object(self, storage_uri: str) -> None:
        """Delete raw document from S3 after successful parse."""
        parts = storage_uri.replace("s3://", "").split("/", 1)
        key = parts[1]
        self.s3_client.delete_object(Bucket=self.bucket, Key=key)
