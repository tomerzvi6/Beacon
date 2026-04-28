import os
from collections.abc import Generator

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, Session


class Base(DeclarativeBase):
    pass


def make_engine(database_url: str | None = None):
    url = database_url or os.environ["DATABASE_URL"]
    return create_engine(url, pool_pre_ping=True)


def get_session(engine) -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session


def set_rls_household(session: Session, household_id: str) -> None:
    """Set the Postgres session variable used by RLS policies."""
    session.execute(text("SET LOCAL app.household_id = :hid"), {"hid": household_id})
