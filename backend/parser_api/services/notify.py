"""Fan a push notification out to a household, minus the person who
triggered it. Kept separate from apns_service so routes don't need to know
about device-token lookup — they just say who and what."""
import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from parser_api.services.apns_service import apns_service
from shared.models import User


def notify_household(
    session: Session,
    household_id: uuid.UUID,
    title: str,
    body: str,
    exclude_user_id: uuid.UUID | None = None,
) -> None:
    filters = [User.household_id == household_id, User.push_token.is_not(None)]
    if exclude_user_id is not None:
        filters.append(User.id != exclude_user_id)
    tokens = session.scalars(select(User.push_token).where(*filters)).all()
    for token in tokens:
        if token:
            apns_service.send(token, title, body)
