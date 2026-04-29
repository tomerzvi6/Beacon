"""Unit tests for SHA-256 hash deduplication in the finalize endpoint."""
import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest

from shared.schemas import FinalizeDocumentIn


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_doc(doc_id, household_id, status="uploaded", content_hash=None, storage_uri=None):
    doc = MagicMock()
    doc.id = doc_id
    doc.household_id = uuid.UUID(household_id)
    doc.uploaded_by = uuid.UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    doc.status = status
    doc.content_hash = content_hash
    doc.storage_uri = storage_uri
    doc.created_at = datetime.now(tz=timezone.utc)
    doc.deleted_at = None
    doc.deleted_by = None
    return doc


# ---------------------------------------------------------------------------
# FinalizeDocumentIn schema validation
# ---------------------------------------------------------------------------


def test_finalize_schema_rejects_short_hash():
    with pytest.raises(Exception):
        FinalizeDocumentIn(
            document_id=uuid.uuid4(),
            sha256_hex="short",
        )


def test_finalize_schema_accepts_64_char_hex():
    valid_hash = "a" * 64
    item = FinalizeDocumentIn(document_id=uuid.uuid4(), sha256_hex=valid_hash)
    assert item.sha256_hex == valid_hash


def test_finalize_schema_rejects_65_chars():
    with pytest.raises(Exception):
        FinalizeDocumentIn(document_id=uuid.uuid4(), sha256_hex="b" * 65)


# ---------------------------------------------------------------------------
# _finalize_one logic (via unit-level import, session mocked)
# ---------------------------------------------------------------------------


@patch("parser_api.routes.uploads.get_storage_service")
def test_finalize_ok_path(mock_storage):
    from parser_api.routes.uploads import _finalize_one

    doc_id = uuid.uuid4()
    hh_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    valid_hash = "c" * 64

    session = MagicMock()
    # First scalar call returns the document, second (duplicate check) returns None
    session.scalar.side_effect = [_make_doc(doc_id, hh_id), None]

    item = FinalizeDocumentIn(document_id=doc_id, sha256_hex=valid_hash)
    result = _finalize_one(item, session, user_id, hh_id)

    assert result.status == "ok"
    assert result.document_id == doc_id


@patch("parser_api.routes.uploads.get_storage_service")
def test_finalize_conflict_returns_existing_id(mock_storage):
    from parser_api.routes.uploads import _finalize_one

    doc_id = uuid.uuid4()
    existing_id = uuid.uuid4()
    hh_id = str(uuid.uuid4())
    user_id = str(uuid.uuid4())
    valid_hash = "d" * 64

    session = MagicMock()
    upload_doc = _make_doc(doc_id, hh_id, storage_uri="local://test")
    existing_doc = _make_doc(existing_id, hh_id, content_hash=valid_hash)
    session.scalar.side_effect = [upload_doc, existing_doc]

    mock_storage.return_value.delete_object = MagicMock()

    item = FinalizeDocumentIn(document_id=doc_id, sha256_hex=valid_hash)
    result = _finalize_one(item, session, user_id, hh_id)

    assert result.status == "conflict"
    assert result.existing_document_id == existing_id
