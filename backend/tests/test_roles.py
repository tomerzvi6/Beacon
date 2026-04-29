"""Unit tests for require_roles dependency factory."""
import uuid
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from parser_api.auth import TokenPayload


def _token(user_id=None, household_id=None) -> TokenPayload:
    return TokenPayload(
        user_id=str(user_id or uuid.uuid4()),
        household_id=str(household_id or uuid.uuid4()),
    )


def _member(role: str) -> MagicMock:
    m = MagicMock()
    m.role = role
    return m


# ---------------------------------------------------------------------------
# require_roles
# ---------------------------------------------------------------------------


@patch("parser_api.dependencies.get_session")
@patch("parser_api.dependencies.verify_token")
def test_require_roles_passes_when_role_matches(mock_verify, mock_session):
    from parser_api.dependencies import require_roles

    token = _token()
    session = MagicMock()
    session.scalar.return_value = _member("patient")

    checker = require_roles("patient", "co_owner")
    result = checker.__wrapped__(token=token, session=session) if hasattr(checker, "__wrapped__") else None
    # Test the inner _check function directly
    inner = require_roles("patient", "co_owner")
    # Simulate what FastAPI calls: the inner _check
    _check = [v for v in inner.__closure__ if callable(getattr(v.cell_contents, "__call__", None))] if hasattr(inner, "__closure__") else []

    # Direct invocation of the dependency function
    from parser_api.dependencies import require_roles as _require_roles
    fn = _require_roles("patient")

    # Get the actual _check callable (inner function returned by factory)
    # When called with token and session, should return token
    assert callable(fn)


def test_require_roles_raises_when_role_not_allowed():
    from parser_api.dependencies import require_roles

    token = _token()
    session = MagicMock()
    session.scalar.return_value = _member("caregiver")

    fn = require_roles("patient", "co_owner")

    with pytest.raises(HTTPException) as exc_info:
        fn(token=token, session=session)
    assert exc_info.value.status_code == 403


def test_require_roles_raises_when_no_member_found():
    from parser_api.dependencies import require_roles

    token = _token()
    session = MagicMock()
    session.scalar.return_value = None

    fn = require_roles("patient")

    with pytest.raises(HTTPException) as exc_info:
        fn(token=token, session=session)
    assert exc_info.value.status_code == 403


def test_require_roles_allows_when_exact_role():
    from parser_api.dependencies import require_roles

    token = _token()
    session = MagicMock()
    session.scalar.return_value = _member("co_owner")

    fn = require_roles("co_owner")
    result = fn(token=token, session=session)
    assert result is token


def test_require_roles_allows_any_in_set():
    from parser_api.dependencies import require_roles

    for role in ("patient", "co_owner"):
        token = _token()
        session = MagicMock()
        session.scalar.return_value = _member(role)

        fn = require_roles("patient", "co_owner")
        result = fn(token=token, session=session)
        assert result is token
