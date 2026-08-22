"""Tests for POST /v1/auth/dev — the no-provider local testing auth path.

Exists because Sign In with Apple needs a paid Apple Developer Program
membership even for a personal-team device install, and this is the only
way to exercise the real backend-synced app without paying for one.
"""
import uuid
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from shared.schemas import DevAuthIn


def test_refuses_outside_development():
    from parser_api.routes.auth import exchange_dev_token
    from parser_api.config import settings

    original = settings.environment
    settings.environment = "production"
    try:
        with pytest.raises(HTTPException) as exc:
            exchange_dev_token(DevAuthIn(email="a@b.com"), session=MagicMock())
        assert exc.value.status_code == 404
    finally:
        settings.environment = original


def test_rejects_invalid_email():
    from parser_api.routes.auth import exchange_dev_token
    from parser_api.config import settings

    original = settings.environment
    settings.environment = "development"
    try:
        session = MagicMock()
        session.scalar.return_value = None
        with pytest.raises(HTTPException) as exc:
            exchange_dev_token(DevAuthIn(email="not-an-email"), session=session)
        assert exc.value.status_code == 400
    finally:
        settings.environment = original


def test_creates_household_and_user_on_first_call():
    from parser_api.routes.auth import exchange_dev_token
    from parser_api.config import settings

    original = settings.environment
    settings.environment = "development"
    try:
        session = MagicMock()
        member = MagicMock(role="patient")
        # First scalar() call looks up an existing user (none yet); second
        # looks up the freshly created membership row.
        session.scalar.side_effect = [None, member]

        with patch("parser_api.routes.auth.create_token", return_value=("jwt-token", 3600)):
            result = exchange_dev_token(
                DevAuthIn(email="Test@Example.com", display_name="בודק"), session=session
            )

        assert result.access_token == "jwt-token"
        assert result.user.role == "patient"
        assert result.user.full_name == "בודק"

        added_types = [type(call.args[0]).__name__ for call in session.add.call_args_list]
        assert "Household" in added_types
        assert "User" in added_types
        assert "HouseholdMember" in added_types
        assert "AuditLog" in added_types

        # google_user_id carries the lowercased, "dev:"-prefixed email —
        # reusing the existing unique column rather than a new schema field.
        user_call = next(c for c in session.add.call_args_list if type(c.args[0]).__name__ == "User")
        assert user_call.args[0].google_user_id == "dev:test@example.com"
    finally:
        settings.environment = original


def test_reuses_existing_user_on_second_call():
    from parser_api.routes.auth import exchange_dev_token
    from parser_api.config import settings

    original = settings.environment
    settings.environment = "development"
    try:
        existing_user = MagicMock(
            id=uuid.uuid4(), household_id=uuid.uuid4(), display_name="בודק",
        )
        member = MagicMock(role="co_owner")
        session = MagicMock()
        session.scalar.side_effect = [existing_user, member]

        with patch("parser_api.routes.auth.create_token", return_value=("jwt-token", 3600)):
            result = exchange_dev_token(DevAuthIn(email="test@example.com"), session=session)

        assert result.user.id == existing_user.id
        assert result.user.role == "co_owner"
        # No new household/user should be created for a returning dev user.
        added_types = [type(call.args[0]).__name__ for call in session.add.call_args_list]
        assert "Household" not in added_types
        assert "User" not in added_types
    finally:
        settings.environment = original
