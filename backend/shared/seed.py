"""
Demo seed — mirrors MockDataSeeder.swift.
Run once against a fresh DB:
    DATABASE_URL=... python -m shared.seed
"""
import os
import uuid
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from shared.models import (
    DoseEvent,
    Household,
    Medication,
    Task,
    User,
)


def seed(database_url: str | None = None) -> None:
    url = database_url or os.environ["DATABASE_URL"]
    engine = create_engine(url)

    with Session(engine) as s:
        if s.query(Household).first():
            print("DB already seeded — skipping.")
            return

        household = Household(id=uuid.uuid4())
        s.add(household)

        ronit = User(
            id=uuid.uuid4(),
            apple_user_id="demo_ronit",
            display_name="רונית",
            role="primary_caregiver",
            household_id=household.id,
            locale="he_IL",
        )
        s.add(ronit)

        now = datetime.now(tz=timezone.utc)

        tasks = [
            Task(
                id=uuid.uuid4(),
                household_id=household.id,
                title_he="לתאם CT בית חולים",
                category="appointment",
                status="approved",
                approved_by=ronit.id,
                approved_at=now,
            ),
            Task(
                id=uuid.uuid4(),
                household_id=household.id,
                title_he="לקחת זריקת Neulasta",
                category="medication",
                status="suggested",
            ),
            Task(
                id=uuid.uuid4(),
                household_id=household.id,
                title_he="בדיקת דם שגרתית",
                category="test",
                status="suggested",
            ),
        ]
        s.add_all(tasks)

        oxycontin = Medication(
            id=uuid.uuid4(),
            household_id=household.id,
            name_he="אוקסיקונטין",
            dosage="10mg",
            schedule={"times": ["08:00", "12:00", "18:00"]},
        )
        s.add(oxycontin)

        for hour in (8, 12, 18):
            s.add(DoseEvent(
                id=uuid.uuid4(),
                medication_id=oxycontin.id,
                scheduled_at=now.replace(hour=hour, minute=0, second=0, microsecond=0),
            ))

        s.commit()
        print(f"Seeded household {household.id} with user רונית.")


if __name__ == "__main__":
    seed()
