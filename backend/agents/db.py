"""DB connection for agents — uses agent_role (restricted, no PHI text)."""
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

_engine = None


def get_engine():
    global _engine
    if _engine is None:
        _engine = create_engine(os.environ["DATABASE_URL"], pool_pre_ping=True)
    return _engine


def get_session() -> Session:
    return Session(get_engine())
