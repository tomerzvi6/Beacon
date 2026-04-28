"""OCR service abstraction (Textract for prod, Tesseract for dev)."""
import io

from parser_api.config import settings


class OCRService:
    def __init__(self):
        self.mode = settings.ocr_mode

    def extract_text(self, file_bytes: bytes, mime_type: str) -> str:
        """Extract text from PDF or image."""
        if self.mode == "textract":
            return self._extract_with_textract(file_bytes, mime_type)
        else:
            return self._extract_with_tesseract(file_bytes, mime_type)

    def _extract_with_textract(self, file_bytes: bytes, mime_type: str) -> str:
        """AWS Textract — for production (Hebrew support)."""
        import boto3

        client = boto3.client("textract", region_name=settings.aws_region)
        response = client.detect_document_text(Document={"Bytes": file_bytes})

        text_blocks = [block["Text"] for block in response["Blocks"] if block["BlockType"] == "LINE"]
        return "\n".join(text_blocks)

    def _extract_with_tesseract(self, file_bytes: bytes, mime_type: str) -> str:
        """Tesseract — for local dev (requires pytesseract + tesseract-ocr installed)."""
        import pytesseract
        from PIL import Image

        if mime_type.startswith("application/pdf"):
            import pdf2image

            images = pdf2image.convert_from_bytes(file_bytes)
            texts = [pytesseract.image_to_string(img, lang="heb+eng") for img in images]
            return "\n".join(texts)
        else:
            image = Image.open(io.BytesIO(file_bytes))
            return pytesseract.image_to_string(image, lang="heb+eng")
