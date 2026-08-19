"""Regression tests for cross-household access bugs found in the
open-kritt security scan: approve_task/claim_task/mark_dose_taken/
local_upload were missing household scoping, and parse_document didn't
check document privacy the way get_document already did.
"""
import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _token(user_id=None, household_id=None):
    from parser_api.auth import TokenPayload
    return TokenPayload(
        user_id=str(user_id or uuid.uuid4()),
        household_id=str(household_id or uuid.uuid4()),
    )


def _task(household_id):
    t = MagicMock()
    t.id = uuid.uuid4()
    t.household_id = uuid.UUID(household_id)
    t.title_he = "קניית תרופות"
    t.description_he = None
    t.category = "logistics"
    t.kind = "logistics"
    t.origin = "ai_suggestion"
    t.due_at = None
    t.status = "suggested"
    t.created_at = datetime.now(tz=timezone.utc)
    t.original_text = None
    t.edited_by_user = False
    t.claimed_by = None
    t.claimed_at = None
    t.approved_by = None
    t.approved_at = None
    return t


def _doc(household_id, is_private=False, uploaded_by=None, status_="uploaded"):
    d = MagicMock()
    d.id = uuid.uuid4()
    d.household_id = uuid.UUID(household_id)
    d.is_private = is_private
    d.uploaded_by = uploaded_by or uuid.uuid4()
    d.status = status_
    return d


def _dose():
    d = MagicMock()
    d.id = uuid.uuid4()
    d.medication = MagicMock()
    d.medication.household_id = uuid.uuid4()
    return d


# ---------------------------------------------------------------------------
# approve_task / claim_task — Task.household_id was missing from the query
# ---------------------------------------------------------------------------


def test_approve_task_404s_for_other_household():
    from parser_api.routes.tasks import approve_task

    owner_hh = str(uuid.uuid4())
    attacker = _token(household_id=str(uuid.uuid4()))  # different household
    task = _task(owner_hh)

    session = MagicMock()
    # Real query would filter by household_id and find nothing.
    session.query.return_value.filter.return_value.first.return_value = None

    with pytest.raises(HTTPException) as exc:
        approve_task(str(task.id), session=session, user=attacker)
    assert exc.value.status_code == 404


def test_approve_task_succeeds_for_owning_household():
    from parser_api.routes.tasks import approve_task

    hh = str(uuid.uuid4())
    owner = _token(household_id=hh)
    task = _task(hh)

    session = MagicMock()
    session.query.return_value.filter.return_value.first.return_value = task

    result = approve_task(str(task.id), session=session, user=owner)
    assert task.status == "approved"
    assert result is not None


def test_claim_task_404s_for_other_household():
    from parser_api.routes.tasks import claim_task

    owner_hh = str(uuid.uuid4())
    attacker = _token(household_id=str(uuid.uuid4()))
    task = _task(owner_hh)

    session = MagicMock()
    session.query.return_value.filter.return_value.first.return_value = None

    with pytest.raises(HTTPException) as exc:
        claim_task(str(task.id), session=session, user=attacker)
    assert exc.value.status_code == 404


def test_claim_task_succeeds_for_owning_household():
    from parser_api.routes.tasks import claim_task

    hh = str(uuid.uuid4())
    owner = _token(household_id=hh)
    task = _task(hh)

    session = MagicMock()
    session.query.return_value.filter.return_value.first.return_value = task

    claim_task(str(task.id), session=session, user=owner)
    assert task.claimed_by == uuid.UUID(owner.user_id)


# ---------------------------------------------------------------------------
# parse_document — was missing the is_private/uploaded_by check that
# get_document already had.
# ---------------------------------------------------------------------------


@patch("parser_api.routes.documents._caller_role")
def test_parse_document_403s_for_private_doc_from_other_member(mock_role):
    from parser_api.routes.documents import parse_document

    hh = str(uuid.uuid4())
    caregiver = _token(household_id=hh)
    # Private doc uploaded by a different household member.
    doc = _doc(hh, is_private=True, uploaded_by=uuid.uuid4())

    session = MagicMock()
    session.scalar.return_value = doc
    mock_role.return_value = "caregiver"
    request = MagicMock()

    with pytest.raises(HTTPException) as exc:
        parse_document.__wrapped__(request, str(doc.id), session=session, user=caregiver)
    assert exc.value.status_code == 403


@patch("parser_api.routes.documents._caller_role")
def test_parse_document_404s_for_other_household(mock_role):
    from parser_api.routes.documents import parse_document

    attacker = _token()
    session = MagicMock()
    session.scalar.return_value = None  # household filter found nothing
    mock_role.return_value = "caregiver"
    request = MagicMock()

    with pytest.raises(HTTPException) as exc:
        parse_document.__wrapped__(request, str(uuid.uuid4()), session=session, user=attacker)
    assert exc.value.status_code == 404


# ---------------------------------------------------------------------------
# mark_dose_taken — DoseEvent has no household_id column; must join through
# Medication. Also regression-covers the old `session.query(dose.medication)`
# bug (querying an instance instead of the Medication class).
# ---------------------------------------------------------------------------


def test_mark_dose_taken_404s_for_other_household():
    from parser_api.routes.doses import mark_dose_taken

    attacker = _token()
    session = MagicMock()
    session.query.return_value.join.return_value.filter.return_value.first.return_value = None

    with pytest.raises(HTTPException) as exc:
        mark_dose_taken(str(uuid.uuid4()), session=session, user=attacker)
    assert exc.value.status_code == 404


def test_mark_dose_taken_succeeds_and_reads_household_via_relationship():
    from parser_api.routes.doses import mark_dose_taken

    owner = _token()
    dose = _dose()
    dose.medication.household_id = uuid.UUID(owner.household_id)

    session = MagicMock()
    session.query.return_value.join.return_value.filter.return_value.first.return_value = dose

    result = mark_dose_taken(str(dose.id), session=session, user=owner)
    assert dose.taken_at is not None
    assert result["dose_event_id"] == str(dose.id)
    session.commit.assert_called()


# ---------------------------------------------------------------------------
# local_upload — was completely unauthenticated with no ownership check.
# ---------------------------------------------------------------------------


def test_local_upload_404s_for_other_household():
    import asyncio
    from parser_api.routes.uploads import local_upload
    from parser_api.services.storage_service import LocalDiskStorageService

    attacker = _token()
    doc_id = uuid.uuid4()

    session = MagicMock()
    session.scalar.return_value = None  # household filter found nothing
    request = MagicMock()

    fake_storage = MagicMock(spec=LocalDiskStorageService)
    with patch(
        "parser_api.services.storage_service.get_storage_service",
        return_value=fake_storage,
    ):
        with pytest.raises(HTTPException) as exc:
            asyncio.run(
                local_upload.__wrapped__(str(doc_id), request, session=session, user=attacker)
            )
    assert exc.value.status_code == 404


def test_local_upload_409s_when_already_finalized():
    import asyncio
    from parser_api.routes.uploads import local_upload
    from parser_api.services.storage_service import LocalDiskStorageService

    hh = str(uuid.uuid4())
    owner = _token(household_id=hh)
    doc = _doc(hh, status_="finalized")

    session = MagicMock()
    session.scalar.return_value = doc
    request = MagicMock()

    fake_storage = MagicMock(spec=LocalDiskStorageService)
    with patch(
        "parser_api.services.storage_service.get_storage_service",
        return_value=fake_storage,
    ):
        with pytest.raises(HTTPException) as exc:
            asyncio.run(
                local_upload.__wrapped__(str(doc.id), request, session=session, user=owner)
            )
    assert exc.value.status_code == 409
