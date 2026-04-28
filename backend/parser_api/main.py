from fastapi import FastAPI, HTTPException, status
from fastapi.exceptions import RequestValidationError

from parser_api.routes import documents, doses, symptoms, tasks, uploads

app = FastAPI(title="Beacon Parser API", version="0.1.0")

# Register routes
app.include_router(uploads.router)
app.include_router(documents.router)
app.include_router(tasks.router)
app.include_router(symptoms.router)
app.include_router(doses.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "parser_api"}
