"""DB connection for agents — uses agent_role (restricted, no PHI text)."""
import os

from sqlalchemy import create_engine
from sqlalchemy.orm import Session


def get_engine():
    url = os.environ["DATABASE_URL"]
    return create_engine(url, pool_pre_ping=True)


def get_session() -> Session:
    return Session(get_engine())
