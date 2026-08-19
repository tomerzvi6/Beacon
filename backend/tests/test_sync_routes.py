"""Regression tests for the Phase 9.6 sync build-out: calendar, feed,
caregiver layer, medications, and the task create/complete/dismiss and dose
materialize additions. Mirrors the MagicMock-session style already used in
test_household_isolation.py / test_invite_redeem.py — these are unit tests
against the route functions, not integration tests against a real DB.
"""
import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException


def _token(user_id=None, household_id=None):
    from parser_api.auth import TokenPayload
    return TokenPayload(
        user_id=str(user_id or uuid.uuid4()),
        household_id=str(household_id or uuid.uuid4()),
    )


# ---------------------------------------------------------------------------
# Calendar (schedule_events)
# ---------------------------------------------------------------------------


def _event(household_id):
    e = MagicMock()
    e.id = uuid.uuid4()
    e.household_id = uuid.UUID(household_id)
    e.title = "בדיקת דם"
    e.starts_at = datetime.now(tz=timezone.utc)
    e.kind = "medical"
    e.location_name = None
    e.companion_user_id = None
    e.subtitle = None
    e.created_at = datetime.now(tz=timezone.utc)
    return e


def test_patch_event_404_for_other_household():
    from parser_api.routes.schedule import patch_event
    from shared.schemas import ScheduleEventPatchIn

    owner_hh = str(uuid.uuid4())
    attacker = _token(household_id=str(uuid.uuid4()))
    session = MagicMock()
    session.scalar.return_value = None  # query filtered by attacker's household finds nothing

    with pytest.raises(HTTPException) as exc:
        patch_event(str(uuid.uuid4()), ScheduleEventPatchIn(title="x"), session=session, user=attacker)
    assert exc.value.status_code == 404


def test_patch_event_updates_only_provided_fields():
    from parser_api.routes.schedule import patch_event
    from shared.schemas import ScheduleEventPatchIn

    hh = str(uuid.uuid4())
    owner = _token(household_id=hh)
    event = _event(hh)
    session = MagicMock()
    session.scalar.return_value = event

    result = patch_event(str(event.id), ScheduleEventPatchIn(title="עדכון"), session=session, user=owner)
    assert result.title == "עדכון"
    assert result.kind == "medical"  # untouched


# ---------------------------------------------------------------------------
# Feed
# ---------------------------------------------------------------------------


def _post(household_id, author_id=None):
    p = MagicMock()
    p.id = uuid.uuid4()
    p.household_id = uuid.UUID(household_id)
    p.author_user_id = author_id or uuid.uuid4()
    p.body = "היום היה יום טוב"
    p.status = "stable"
    p.audience = "family_only"
    p.posted_at = datetime.now(tz=timezone.utc)
    p.comments = []
    p.reactions = []
    return p


def test_feed_post_not_found_cross_household():
    from parser_api.routes.feed import add_comment
    from shared.schemas import FeedCommentIn

    attacker = _token(household_id=str(uuid.uuid4()))
    session = MagicMock()
    session.scalar.return_value = None

    with pytest.raises(HTTPException) as exc:
        add_comment(str(uuid.uuid4()), FeedCommentIn(body="hi"), session=session, user=attacker)
    assert exc.value.status_code == 404


def test_feed_reaction_counts_and_my_reactions():
    from parser_api.routes.feed import _to_out

    hh = str(uuid.uuid4())
    post = _post(hh)
    viewer = uuid.uuid4()
    other = uuid.uuid4()

    r1 = MagicMock(reaction="heart", user_id=viewer)
    r2 = MagicMock(reaction="heart", user_id=other)
    r3 = MagicMock(reaction="hug", user_id=other)
    post.reactions = [r1, r2, r3]

    out = _to_out(post, viewer)
    assert out.heart_count == 2
    assert out.hug_count == 1
    assert out.my_reactions == ["heart"]


def test_react_to_post_duplicate_tap_is_idempotent():
    """A second identical reaction hits the unique constraint (IntegrityError)
    and must not raise — the route swallows it and returns the post unchanged."""
    from sqlalchemy.exc import IntegrityError

    from parser_api.routes.feed import react_to_post
    from shared.schemas import FeedReactionIn

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    post = _post(hh)

    session = MagicMock()
    session.scalar.return_value = post
    session.begin_nested.return_value.__enter__.side_effect = IntegrityError("dup", {}, Exception())

    result = react_to_post(str(post.id), FeedReactionIn(reaction="heart"), session=session, user=user)
    assert result.id == post.id
    session.commit.assert_called()  # still commits the outer transaction


# ---------------------------------------------------------------------------
# Caregiver layer
# ---------------------------------------------------------------------------


def _profile(household_id):
    p = MagicMock()
    p.id = uuid.uuid4()
    p.household_id = uuid.UUID(household_id)
    p.display_name = "מריה"
    p.relation_title = "מטפלת סיעודית"
    p.preferred_language = "english"
    p.is_active = True
    p.created_at = datetime.now(tz=timezone.utc)
    return p


def test_create_checkin_rejects_caregiver_from_other_household():
    from parser_api.routes.caregivers import create_checkin
    from shared.schemas import CaregiverCheckInIn

    attacker = _token(household_id=str(uuid.uuid4()))
    session = MagicMock()
    session.scalar.return_value = None  # profile lookup scoped to attacker's household fails

    body = CaregiverCheckInIn(
        caregiver_id=uuid.uuid4(),
        meal_status="ateWell",
        hydration_status="drankEnough",
        sleep_status="sleptWell",
        pain_level=0,
        nausea_level=0,
        fatigue_level=0,
        medication_status="taken",
        original_language="english",
        translated_summary_hebrew="אכל טוב, שתה מספיק, ישן טוב.",
    )
    with pytest.raises(HTTPException) as exc:
        create_checkin(body, session=session, user=attacker)
    assert exc.value.status_code == 404


def test_create_checkin_flags_audit_log_when_attention_needed():
    from parser_api.routes.caregivers import create_checkin
    from shared.schemas import CaregiverCheckInIn

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    profile = _profile(hh)

    session = MagicMock()
    session.scalar.return_value = profile

    body = CaregiverCheckInIn(
        caregiver_id=profile.id,
        meal_status="didNotEat",
        hydration_status="didNotDrink",
        sleep_status="sleptPoorly",
        pain_level=8,
        nausea_level=0,
        fatigue_level=0,
        medication_status="missed",
        original_language="tagalog",
        translated_summary_hebrew="כאב חזק, תרופה לא נלקחה.",
        attention_level="urgent",
        alert_reasons=["כאב גבוה (8/10)", "תרופה לא נלקחה"],
    )
    result = create_checkin(body, session=session, user=user)
    assert result.attention_level == "urgent"
    # commit called at least twice: once for the checkin, once for the audit log
    assert session.commit.call_count >= 2


# ---------------------------------------------------------------------------
# Medications
# ---------------------------------------------------------------------------


def test_patch_medication_404_for_other_household():
    from parser_api.routes.medications import patch_medication
    from shared.schemas import MedicationPatchIn

    attacker = _token(household_id=str(uuid.uuid4()))
    session = MagicMock()
    session.scalar.return_value = None

    with pytest.raises(HTTPException) as exc:
        patch_medication(str(uuid.uuid4()), MedicationPatchIn(stock_count=3), session=session, user=attacker)
    assert exc.value.status_code == 404


def test_create_medication_encodes_dosing_times_into_schedule():
    from parser_api.routes.medications import create_medication
    from shared.schemas import MedicationIn

    hh = str(uuid.uuid4())
    user = _token(household_id=hh)
    session = MagicMock()

    body = MedicationIn(name_he="אקמול", dosing_times=["08:00", "20:00"])
    result = create_medication(body, session=session, user=user)
    assert result.schedule == {"dosing_times": ["08:00", "20:00"]}


# ---------------------------------------------------------------------------
# Doses — status computation + materialize-today idempotency
# ---------------------------------------------------------------------------


def test_dose_status_computation():
    from parser_api.routes.doses import _dose_status

    now = datetime.now(tz=timezone.utc)
    upcoming = MagicMock(taken_at=None, scheduled_at=now.replace(hour=23, minute=59))
    missed = MagicMock(taken_at=None, scheduled_at=now.replace(hour=0, minute=1))
    taken = MagicMock(taken_at=now, scheduled_at=now.replace(hour=0, minute=1))

    assert _dose_status(upcoming, now) == "upcoming"
    assert _dose_status(missed, now) == "missed"
    assert _dose_status(taken, now) == "taken"


# ---------------------------------------------------------------------------
# Tasks — create/complete/dismiss
# ---------------------------------------------------------------------------


def test_create_task_is_manual_and_pre_approved():
    from parser_api.routes.tasks import create_task
    from shared.schemas import TaskCreateIn

    user = _token()
    session = MagicMock()

    body = TaskCreateIn(title_he="לתאם הסעה", kind="logistics")
    result = create_task(body, session=session, user=user)
    assert result.origin == "manual"
    assert result.status == "approved"
    assert result.kind == "logistics"


def _task(household_id):
    t = MagicMock()
    t.id = uuid.uuid4()
    t.household_id = uuid.UUID(household_id)
    t.title_he = "קניית תרופות"
    t.description_he = None
    t.category = "logistics"
    t.kind = "logistics"
    t.origin = "manual"
    t.due_at = None
    t.status = "approved"
    t.created_at = datetime.now(tz=timezone.utc)
    t.original_text = None
    t.edited_by_user = False
    t.claimed_by = None
    t.claimed_at = None
    t.approved_by = None
    t.approved_at = None
    t.completed_at = None
    return t


def test_complete_task_404_for_other_household():
    from parser_api.routes.tasks import complete_task

    attacker = _token(household_id=str(uuid.uuid4()))
    session = MagicMock()
    session.query.return_value.filter.return_value.first.return_value = None

    with pytest.raises(HTTPException) as exc:
        complete_task(str(uuid.uuid4()), session=session, user=attacker)
    assert exc.value.status_code == 404


def test_complete_task_sets_done_status():
    from parser_api.routes.tasks import complete_task

    hh = str(uuid.uuid4())
    owner = _token(household_id=hh)
    task = _task(hh)
    session = MagicMock()
    session.query.return_value.filter.return_value.first.return_value = task

    result = complete_task(str(task.id), session=session, user=owner)
    assert result.status == "done"
    assert result.completed_at is not None


def test_dismiss_task_sets_dismissed_status():
    from parser_api.routes.tasks import dismiss_task

    hh = str(uuid.uuid4())
    owner = _token(household_id=hh)
    task = _task(hh)
    session = MagicMock()
    session.query.return_value.filter.return_value.first.return_value = task

    result = dismiss_task(str(task.id), session=session, user=owner)
    assert result.status == "dismissed"
