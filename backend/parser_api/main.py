from fastapi import FastAPI

from parser_api.middleware import apply_middleware
from parser_api.routes import documents, doses, households, symptoms, tasks, uploads, users

app = FastAPI(title="Beacon Parser API", version="0.1.0")

apply_middleware(app)

app.include_router(uploads.router)
app.include_router(documents.router)
app.include_router(tasks.router)
app.include_router(symptoms.router)
app.include_router(doses.router)
app.include_router(users.router)
app.include_router(households.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "parser_api"}
