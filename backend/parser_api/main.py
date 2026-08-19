import os
import subprocess

from fastapi import FastAPI

from parser_api.config import settings
from parser_api.middleware import apply_middleware
from parser_api.routes import (
    auth,
    caregivers,
    documents,
    doses,
    feed,
    households,
    medications,
    schedule,
    symptoms,
    tasks,
    uploads,
    users,
)


def _verify_runtime_secrets() -> None:
    """Refuse to boot in non-development environments when JWT_SIGNING_KEY
    was not explicitly configured. config.py no longer falls back to a
    fixed, guessable key — an unconfigured deployment now gets a random
    per-process key instead, which is safe but invalidates every session on
    each restart/redeploy. That's a bad (if harmless) production surprise,
    so we still fail loudly here rather than let it happen silently.
    """
    if settings.environment != "development" and "JWT_SIGNING_KEY" not in os.environ:
        raise RuntimeError(
            "JWT_SIGNING_KEY must be set in non-development environments "
            f"(ENVIRONMENT={settings.environment!r}). Refusing to boot with "
            "an auto-generated key."
        )


def _resolve_commit_sha() -> str:
    """Best-effort short SHA at startup. Reads BEACON_COMMIT first
    (preferred — set at build/deploy time), then GIT_COMMIT (legacy),
    then shells out to `git rev-parse` as a last resort.
    """
    for var in ("BEACON_COMMIT", "GIT_COMMIT"):
        if value := os.environ.get(var):
            return value[:12]
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL,
            timeout=2,
        ).decode().strip()
    except Exception:
        return "unknown"


_verify_runtime_secrets()
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
app.include_router(schedule.router)
app.include_router(feed.router)
app.include_router(caregivers.router)
app.include_router(medications.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "parser_api", "commit": COMMIT_SHA}
