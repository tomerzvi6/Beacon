"""
Embedding utility for the Chief Agent.

Provider selection via EMBEDDING_PROVIDER env var:
  "voyage"  → Voyage AI voyage-2  (default)
  "openai"  → OpenAI text-embedding-3-small (fallback)
"""
import os
from functools import lru_cache


def embed_text(text: str) -> list[float]:
    """Return a 1536-dim embedding vector for *text*."""
    provider = os.environ.get("EMBEDDING_PROVIDER", "voyage").lower()
    if provider == "voyage":
        return _embed_voyage(text)
    return _embed_openai(text)


@lru_cache(maxsize=1)
def _get_voyage_client():
    import voyageai  # type: ignore
    return voyageai.Client(api_key=os.environ.get("VOYAGE_API_KEY", ""))


@lru_cache(maxsize=1)
def _get_openai_client():
    import openai  # type: ignore
    return openai.OpenAI(api_key=os.environ.get("OPENAI_API_KEY", ""))


def _embed_voyage(text: str) -> list[float]:
    try:
        client = _get_voyage_client()
        result = client.embed([text], model=os.environ.get("EMBEDDING_MODEL", "voyage-2"))
        return result.embeddings[0]
    except Exception:
        return _embed_openai(text)


def _embed_openai(text: str) -> list[float]:
    resp = _get_openai_client().embeddings.create(
        input=text,
        model=os.environ.get("EMBEDDING_MODEL", "text-embedding-3-small"),
    )
    return resp.data[0].embedding
