"""Unit tests for per-module caregiver permission enforcement and real
membership revocation — the two gaps found while simulating multi-caregiver
households (patient/co_owner always have full access; a caregiver's access
is governed by household_members.permissions and disappears the moment
their household_members row is deleted, not just on the device that revoked
them).
"""
import uuid
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from parser_api.auth import TokenPayload


def _token(user_id=None, household_id=None) -> TokenPayload:
    return TokenPayload(
        user_id=str(user_id or uuid.uuid4()),
        household_id=str(household_id or uuid.uuid4()),
    )


def _member(role: str, permissions=None) -> MagicMock:
    m = MagicMock()
    m.role = role
    m.permissions = permissions
    return m


# ---------------------------------------------------------------------------
# get_session membership re-check (revocation effectiveness)
# ---------------------------------------------------------------------------


def test_set_rls_and_verify_membership_raises_when_member_missing():
    from parser_api.dependencies import _set_rls_and_verify_membership

    session = MagicMock()
    session.scalar.return_value = None

    with pytest.raises(HTTPException) as exc:
        _set_rls_and_verify_membership(session, _token())
    assert exc.value.status_code == 403


def test_set_rls_and_verify_membership_passes_when_member_present():
    from parser_api.dependencies import _set_rls_and_verify_membership

    session = MagicMock()
    session.scalar.return_value = _member("caregiver")

    _set_rls_and_verify_membership(session, _token())  # no raise


# ---------------------------------------------------------------------------
# require_module_access
# ---------------------------------------------------------------------------


def test_module_access_patient_always_passes_regardless_of_permissions():
    from parser_api.dependencies import require_module_access

    session = MagicMock()
    session.scalar.return_value = _member("patient", permissions=None)
    token = _token()

    fn = require_module_access("medicalVault", 2)
    assert fn(token=token, session=session) is token


def test_module_access_co_owner_always_passes():
    from parser_api.dependencies import require_module_access

    session = MagicMock()
    session.scalar.return_value = _member("co_owner", permissions=None)

    fn = require_module_access("medications", 2)
    fn(token=_token(), session=session)  # no raise


def test_module_access_caregiver_below_required_level_blocked():
    from parser_api.dependencies import require_module_access

    session = MagicMock()
    session.scalar.return_value = _member("caregiver", permissions={"medications": 1})

    fn = require_module_access("medications", 2)
    with pytest.raises(HTTPException) as exc:
        fn(token=_token(), session=session)
    assert exc.value.status_code == 403


def test_module_access_caregiver_at_required_level_passes():
    from parser_api.dependencies import require_module_access

    session = MagicMock()
    session.scalar.return_value = _member("caregiver", permissions={"medications": 2})

    fn = require_module_access("medications", 2)
    fn(token=_token(), session=session)  # no raise


def test_module_access_caregiver_none_level_blocks_even_read():
    from parser_api.dependencies import require_module_access

    session = MagicMock()
    session.scalar.return_value = _member("caregiver", permissions={"medicalVault": 0})

    fn = require_module_access("medicalVault", 1)
    with pytest.raises(HTTPException) as exc:
        fn(token=_token(), session=session)
    assert exc.value.status_code == 403


def test_module_access_caregiver_missing_module_key_defaults_to_read():
    from parser_api.dependencies import require_module_access

    session = MagicMock()
    # permissions dict exists but has no entry for this module — must
    # default to read(1), matching MemberRole.defaultMember on iOS.
    session.scalar.return_value = _member("caregiver", permissions={"feed": 2})

    read_check = require_module_access("schedule", 1)
    read_check(token=_token(), session=session)  # no raise — defaults to read

    write_check = require_module_access("schedule", 2)
    with pytest.raises(HTTPException) as exc:
        write_check(token=_token(), session=session)
    assert exc.value.status_code == 403


def test_module_access_raises_when_member_missing():
    from parser_api.dependencies import require_module_access

    session = MagicMock()
    session.scalar.return_value = None

    fn = require_module_access("tasks", 1)
    with pytest.raises(HTTPException) as exc:
        fn(token=_token(), session=session)
    assert exc.value.status_code == 403


# ---------------------------------------------------------------------------
# DELETE /v1/households/members/{id} (real revocation, not local-only)
# ---------------------------------------------------------------------------


def test_remove_member_deletes_caregiver():
    from parser_api.routes.households import remove_member

    hh = uuid.uuid4()
    target = MagicMock()
    target.id = uuid.uuid4()
    target.role = "caregiver"
    target.user_id = uuid.uuid4()
    target.household_id = hh

    session = MagicMock()
    session.scalar.return_value = target
    caller = _token(household_id=str(hh))

    remove_member(str(target.id), session=session, user=caller)
    session.delete.assert_called_once_with(target)
    session.commit.assert_called()


def test_remove_member_rejects_removing_the_patient():
    from parser_api.routes.households import remove_member

    target = MagicMock()
    target.role = "patient"
    session = MagicMock()
    session.scalar.return_value = target

    with pytest.raises(HTTPException) as exc:
        remove_member(str(uuid.uuid4()), session=session, user=_token())
    assert exc.value.status_code == 400
    session.delete.assert_not_called()


def test_remove_member_rejects_self_removal():
    from parser_api.routes.households import remove_member

    caller = _token()
    target = MagicMock()
    target.role = "co_owner"
    target.user_id = uuid.UUID(caller.user_id)
    session = MagicMock()
    session.scalar.return_value = target

    with pytest.raises(HTTPException) as exc:
        remove_member(str(uuid.uuid4()), session=session, user=caller)
    assert exc.value.status_code == 400
    session.delete.assert_not_called()


def test_remove_member_404_when_not_found():
    from parser_api.routes.households import remove_member

    session = MagicMock()
    session.scalar.return_value = None

    with pytest.raises(HTTPException) as exc:
        remove_member(str(uuid.uuid4()), session=session, user=_token())
    assert exc.value.status_code == 404


# ---------------------------------------------------------------------------
# PATCH /v1/households/members/{id}/permissions
# ---------------------------------------------------------------------------


def test_patch_member_permissions_updates_single_module():
    from parser_api.routes.households import patch_member_permissions
    from shared.schemas import MemberPermissionPatchIn

    target = MagicMock()
    target.id = uuid.uuid4()
    target.role = "caregiver"
    target.user_id = uuid.uuid4()
    target.household_id = uuid.uuid4()
    target.joined_at.isoformat.return_value = "2026-01-01T00:00:00Z"
    target.permissions = {"schedule": 1, "tasks": 1, "medications": 1, "medicalVault": 1, "feed": 1}

    session = MagicMock()
    session.scalar.side_effect = [target, "Display Name"]

    out = patch_member_permissions(
        str(target.id),
        MemberPermissionPatchIn(module="medications", level=2),
        session=session,
        user=_token(),
    )
    assert target.permissions["medications"] == 2
    assert target.permissions["schedule"] == 1  # other modules untouched
    assert out.permissions["medications"] == 2


def test_patch_member_permissions_rejects_non_caregiver():
    from parser_api.routes.households import patch_member_permissions
    from shared.schemas import MemberPermissionPatchIn

    target = MagicMock()
    target.role = "co_owner"
    session = MagicMock()
    session.scalar.return_value = target

    with pytest.raises(HTTPException) as exc:
        patch_member_permissions(
            str(uuid.uuid4()),
            MemberPermissionPatchIn(module="medications", level=2),
            session=session,
            user=_token(),
        )
    assert exc.value.status_code == 400


# ---------------------------------------------------------------------------
# set_rls_household must use a parameterizable call (SET LOCAL x = :param is
# a Postgres syntax error — set_config() is the fix). Regression guard so
# nobody reverts to the broken form.
# ---------------------------------------------------------------------------


def test_set_rls_household_uses_set_config_not_bare_set_local():
    from shared.db import set_rls_household

    session = MagicMock()
    set_rls_household(session, "some-household-id")
    executed_sql = str(session.execute.call_args[0][0])
    assert "set_config" in executed_sql
    assert "SET LOCAL app.household_id = :hid" not in executed_sql
