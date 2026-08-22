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
    """Set the Postgres session variable used by RLS policies.

    Plain `SET LOCAL app.household_id = :hid` is a syntax error — Postgres's
    SET grammar doesn't accept a bind parameter for the value, only a
    literal, so bare `SET LOCAL ... = :hid` fails every single call. This
    was broken since the first backend commit, so every request through
    get_session() 500'd once it reached the DB. set_config() is the
    parameterized equivalent (third arg true = LOCAL, i.e. transaction-scoped).
    """
    session.execute(text("SELECT set_config('app.household_id', :hid, true)"), {"hid": household_id})
