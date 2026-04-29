"""User account management — includes GDPR right-to-erasure."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import (
    AuditLog,
    Document,
    DoseEvent,
    Household,
    Medication,
    SymptomReport,
    Task,
    User,
)

router = APIRouter(prefix="/v1/me", tags=["users"])


@router.delete("", status_code=204)
def delete_me(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> None:
    """
    GDPR right-to-erasure: permanently delete the caller's account and all
    associated PHI.

    If the caller is the last user in their household the entire household
    (documents, tasks, medications, symptoms, dose events) is also deleted.
    If other users share the household, only the caller's user row is removed
    and their claimed/approved task references are nulled out.
    """
    user_uuid = uuid.UUID(user.user_id)
    household_uuid = uuid.UUID(user.household_id)

    db_user = session.query(User).filter(User.id == user_uuid).first()
    if not db_user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    siblings = (
        session.query(User)
        .filter(User.household_id == household_uuid, User.id != user_uuid)
        .count()
    )

    if siblings == 0:
        # Last member — wipe the whole household
        _delete_household(session, household_uuid)
    else:
        # Null-out task references before removing the user row
        session.query(Task).filter(Task.approved_by == user_uuid).update(
            {"approved_by": None}, synchronize_session=False
        )
        session.query(Task).filter(Task.claimed_by == user_uuid).update(
            {"claimed_by": None}, synchronize_session=False
        )
        session.delete(db_user)

    session.add(
        AuditLog(
            actor_type="user",
            actor_id=str(user_uuid),
            action="gdpr_erasure",
            target_table="users",
            target_id=user_uuid,
            household_id=household_uuid,
            metadata_={"siblings_remaining": siblings},
        )
    )
    session.commit()


def _delete_household(session: Session, household_id: uuid.UUID) -> None:
    """Hard-delete all PHI rows for a household in safe dependency order."""
    med_ids = [
        row[0]
        for row in session.query(Medication.id)
        .filter(Medication.household_id == household_id)
        .all()
    ]
    if med_ids:
        session.execute(
            delete(DoseEvent).where(DoseEvent.medication_id.in_(med_ids))
        )

    session.execute(delete(Medication).where(Medication.household_id == household_id))
    session.execute(delete(SymptomReport).where(SymptomReport.household_id == household_id))
    session.execute(delete(Task).where(Task.household_id == household_id))
    session.execute(delete(Document).where(Document.household_id == household_id))
    session.execute(delete(User).where(User.household_id == household_id))
    session.execute(delete(Household).where(Household.id == household_id))
