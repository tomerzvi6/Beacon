"""Tests for the universal 6-digit join flow (POST /v1/households/join).

This is the path that makes a family a family: before it, every Apple
sign-in produced its own private household, so two relatives could never
see the same documents.
"""
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException


def _token(user_id=None, household_id=None):
    from parser_api.auth import TokenPayload
    return TokenPayload(
        user_id=str(user_id or uuid.uuid4()),
        household_id=str(household_id or uuid.uuid4()),
    )


def _invite(household_id, role="caregiver", invitee_user_id=None):
    inv = MagicMock()
    inv.id = uuid.uuid4()
    inv.household_id = household_id
    inv.role = role
    inv.invitee_user_id = invitee_user_id
    inv.used_at = None
    inv.expires_at = datetime.now(tz=timezone.utc) + timedelta(days=1)
    inv.created_by = uuid.uuid4()
    return inv


def _member(household_id, user_id, role="caregiver"):
    m = MagicMock()
    m.id = uuid.uuid4()
    m.household_id = household_id
    m.user_id = user_id
    m.role = role
    m.joined_at = datetime.now(tz=timezone.utc)
    return m


def _call(session, user, code="123456"):
    """Invoke the route past its rate-limit decorator."""
    from parser_api.routes.households import redeem_invite
    from shared.schemas import RedeemInviteIn
    return redeem_invite.__wrapped__(
        MagicMock(), RedeemInviteIn(code=code), session=session, user=user
    )


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


def test_redeem_joins_household_and_returns_fresh_token():
    joiner = _token()
    owner_household = uuid.uuid4()
    invite = _invite(owner_household)
    joining_user = MagicMock()
    joining_user.id = uuid.UUID(joiner.user_id)
    joining_user.household_id = uuid.UUID(joiner.household_id)  # own empty household

    session = MagicMock()
    # invite lookup -> no existing membership -> the User row
    session.scalar.side_effect = [invite, None, joining_user]

    result = _call(session, joiner)

    # The user is repointed at the household they joined — otherwise the
    # next sign-in would send them back to their own empty one.
    assert joining_user.household_id == owner_household
    assert invite.used_at is not None
    assert result.access_token
    assert result.expires_in_seconds > 0
    session.commit.assert_called()


def test_redeem_uses_role_carried_by_the_code():
    """A co-owner code must not silently downgrade the joiner to caregiver."""
    joiner = _token()
    invite = _invite(uuid.uuid4(), role="co_owner")
    joining_user = MagicMock()
    joining_user.id = uuid.UUID(joiner.user_id)

    added = []
    session = MagicMock()
    session.scalar.side_effect = [invite, None, joining_user]
    session.add.side_effect = lambda o: added.append(o)

    _call(session, joiner)

    from shared.models import HouseholdMember
    roles = [o.role for o in added if isinstance(o, HouseholdMember)]
    assert roles == ["co_owner"]


# ---------------------------------------------------------------------------
# Rejections
# ---------------------------------------------------------------------------


def test_redeem_rejects_unknown_or_expired_code():
    session = MagicMock()
    session.scalar.return_value = None

    with pytest.raises(HTTPException) as exc:
        _call(session, _token())
    assert exc.value.status_code == 400


def test_redeem_rejects_targeted_code_used_by_someone_else():
    joiner = _token()
    invite = _invite(uuid.uuid4(), role="co_owner", invitee_user_id=uuid.uuid4())

    session = MagicMock()
    session.scalar.return_value = invite

    with pytest.raises(HTTPException) as exc:
        _call(session, joiner)
    assert exc.value.status_code == 403


def test_redeem_rejects_double_join():
    joiner = _token()
    household = uuid.uuid4()
    invite = _invite(household)

    session = MagicMock()
    session.scalar.side_effect = [invite, _member(household, uuid.UUID(joiner.user_id))]

    with pytest.raises(HTTPException) as exc:
        _call(session, joiner)
    assert exc.value.status_code == 409


def test_redeem_does_not_consume_code_when_join_is_rejected():
    """A rejected attempt must leave the invite usable by its real owner."""
    invite = _invite(uuid.uuid4(), role="co_owner", invitee_user_id=uuid.uuid4())
    session = MagicMock()
    session.scalar.return_value = invite

    with pytest.raises(HTTPException):
        _call(session, _token())
    assert invite.used_at is None


# ---------------------------------------------------------------------------
# Code allocation
# ---------------------------------------------------------------------------


def test_issue_unique_code_skips_a_live_collision():
    """Codes resolve on their own, so two live invites sharing one would
    drop a joiner into the wrong family."""
    from parser_api.routes.households import _issue_unique_code

    session = MagicMock()
    session.scalar.side_effect = [MagicMock(), None]  # first taken, second free

    code, code_hash = _issue_unique_code(session)
    assert len(code) == 6 and code.isdigit()
    assert len(code_hash) == 64
    assert session.scalar.call_count == 2


def test_issue_unique_code_gives_up_rather_than_reusing():
    from parser_api.routes.households import _issue_unique_code

    session = MagicMock()
    session.scalar.return_value = MagicMock()  # every candidate collides

    with pytest.raises(HTTPException) as exc:
        _issue_unique_code(session)
    assert exc.value.status_code == 503
