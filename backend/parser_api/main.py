import os
import subprocess

from fastapi import FastAPI

from parser_api.middleware import apply_middleware
from parser_api.routes import auth, documents, doses, households, symptoms, tasks, uploads, users


def _resolve_commit_sha() -> str:
    """Best-effort short SHA at startup. Falls back to GIT_COMMIT env var."""
    env = os.environ.get("GIT_COMMIT")
    if env:
        return env[:12]
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL,
            timeout=2,
        ).decode().strip()
    except Exception:
        return "unknown"


COMMIT_SHA = _resolve_commit_sha()

app = FastAPI(title="Beacon Parser API", version="0.1.0")

apply_middleware(app)

app.include_router(auth.router)
app.include_router(uploads.router)
app.include_router(documents.router)
app.include_router(tasks.router)
app.include_router(symptoms.router)
app.include_router(doses.router)
app.include_router(users.router)
app.include_router(households.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "parser_api", "commit": COMMIT_SHA}
