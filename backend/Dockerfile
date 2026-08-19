# Beacon Parser API — production image
# Build context: the backend/ directory.
FROM python:3.11-slim

# Tesseract OCR with Hebrew + English language packs (ocr_mode=tesseract)
RUN apt-get update && apt-get install -y --no-install-recommends \
        tesseract-ocr \
        tesseract-ocr-heb \
        tesseract-ocr-eng \
        libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install both packages (shared first — parser_api depends on it)
COPY shared/ ./shared/
COPY parser_api/ ./parser_api/
COPY alembic.ini ./alembic.ini
RUN pip install --no-cache-dir -e ./shared -e ./parser_api

# Local uploads live on a mounted volume in production (see fly.toml)
RUN mkdir -p /data/uploads

EXPOSE 8000

# Run DB migrations, then serve.
CMD ["sh", "-c", "alembic upgrade head && uvicorn parser_api.main:app --host 0.0.0.0 --port 8000"]
