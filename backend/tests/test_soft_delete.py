"""Unit tests for document soft-delete, trash, and restore endpoints."""
import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _doc(household_id, deleted_at=None, is_private=False, uploaded_by=None):
    d = MagicMock()
    d.id = uuid.uuid4()
    d.household_id = uuid.UUID(household_id)
    d.mime_type = "application/pdf"
    d.category_source = None
    d.category_suggested = None
    d.flagged_for_review = False
    d.flag_reason = None
    d.parsed_summary_he = "סיכום בדיקה"
    d.parsed_summary_simple_he = "סיכום פשוט"
    d.created_at = datetime.now(tz=timezone.utc)
    d.parsed_at = datetime.now(tz=timezone.utc)
    d.deleted_at = deleted_at
    d.deleted_by = None
    d.is_private = is_private
    d.uploaded_by = uploaded_by or uuid.uuid4()
    d.status = "parsed"
    d.category = "lab"
    d.filename = "test.pdf"
    return d


def _token(user_id=None, household_id=None):
    from parser_api.auth import TokenPayload
    hh = str(uuid.uuid4()) if not household_id else household_id
    uid = str(uuid.uuid4()) if not user_id else user_id
    return TokenPayload(user_id=uid, household_id=hh)


def _member(role: str):
    m = MagicMock()
    m.role = role
    return m


# ---------------------------------------------------------------------------
# delete_document (soft delete)
# ---------------------------------------------------------------------------


@patch("parser_api.routes.documents._caller_role")
def test_soft_delete_sets_deleted_at(mock_role):
    from parser_api.routes.documents import delete_document

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    doc = _doc(hh)
    session = MagicMock()
    session.scalar.return_value = doc
    mock_role.return_value = "patient"

    delete_document(str(doc.id), session=session, user=user)

    assert doc.deleted_at is not None
    assert doc.deleted_by == uuid.UUID(user.user_id)
    session.commit.assert_called()


@patch("parser_api.routes.documents._caller_role")
def test_soft_delete_caregiver_cannot_delete_private_others(mock_role):
    from parser_api.routes.documents import delete_document

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    # Uploaded by someone else, is_private
    doc = _doc(hh, is_private=True, uploaded_by=uuid.uuid4())
    session = MagicMock()
    session.scalar.return_value = doc
    mock_role.return_value = "caregiver"

    with pytest.raises(HTTPException) as exc:
        delete_document(str(doc.id), session=session, user=user)
    assert exc.value.status_code == 403


@patch("parser_api.routes.documents._caller_role")
def test_soft_delete_404_when_not_found(mock_role):
    from parser_api.routes.documents import delete_document

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    session = MagicMock()
    session.scalar.return_value = None
    mock_role.return_value = "patient"

    with pytest.raises(HTTPException) as exc:
        delete_document(str(uuid.uuid4()), session=session, user=user)
    assert exc.value.status_code == 404


# ---------------------------------------------------------------------------
# restore_document
# ---------------------------------------------------------------------------


def test_restore_clears_deleted_at():
    from parser_api.routes.documents import restore_document

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    doc = _doc(hh, deleted_at=datetime.now(tz=timezone.utc))
    session = MagicMock()
    session.scalar.return_value = doc

    restore_document(str(doc.id), session=session, user=user)

    assert doc.deleted_at is None
    assert doc.deleted_by is None
    session.commit.assert_called()


def test_restore_404_when_not_in_trash():
    from parser_api.routes.documents import restore_document

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    session = MagicMock()
    session.scalar.return_value = None

    with pytest.raises(HTTPException) as exc:
        restore_document(str(uuid.uuid4()), session=session, user=user)
    assert exc.value.status_code == 404
