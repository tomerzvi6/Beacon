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
    AgentRun,
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

        # Demo AgentRun rows — one per agent, all awaiting approval so dashboard isn't empty
        demo_runs = [
            AgentRun(
                agent_name="guardian",
                status="awaiting_approval",
                input_summary={"audit_entries_scanned": 42, "findings_count": 1,
                                "critical": 0, "high": 1, "rls_all_pass": True},
                output_draft={
                    "type": "security_brief",
                    "markdown": (
                        "## 🛡️ דוח אבטחה יומי (DEMO)\n\n"
                        "**✅ RLS תקין** — כל 4 בדיקות עברו.\n\n"
                        "### ממצאים\n"
                        "- [HIGH] גישה מחוץ לשעות עבודה: actor_id=demo_system בשעה 02:14"
                    ),
                    "findings": [{"finding": "off_hours_access", "severity": "high",
                                  "actor_id": "demo_system", "local_time": "02:14"}],
                    "rls_results": {"tasks.title_he_blocked": True,
                                    "documents.raw_ocr_text_blocked": True},
                },
            ),
            AgentRun(
                agent_name="customer_success",
                status="awaiting_approval",
                input_summary={"mode": "proactive", "unclaimed_count": 2, "at_risk_count": 0},
                output_draft={
                    "type": "push",
                    "user_id": str(household.id),
                    "body_he": "יש משימה שממתינה 3 ימים: תיאום CT. כדאי לטפל בה היום?",
                    "cohort_summary_he": "2 משימות לא מטופלות מעל 48 שעות.",
                },
            ),
            AgentRun(
                agent_name="product",
                status="awaiting_approval",
                input_summary={"period": "last 7 days", "active_households": 1,
                               "engagement_at_risk": 0},
                output_draft={
                    "type": "product_report",
                    "markdown": (
                        "## 📊 דוח מוצר שבועי (DEMO)\n\n"
                        "| מדד | ערך |\n|---|---|\n"
                        "| משקי בית פעילים | 1 |\n"
                        "| השלמת משימות | 33% |\n"
                        "| היענות לתרופות | 67% |\n\n"
                        "### המלצות\n1. לשפר onboarding לאישור משימות\n"
                    ),
                },
            ),
            AgentRun(
                agent_name="creative",
                status="awaiting_approval",
                input_summary={"mode": "weekly_calendar", "pieces_count": 3,
                               "request_preview": "לוח תוכן שבועי"},
                output_draft={
                    "type": "content_draft",
                    "mode": "weekly_calendar",
                    "calendar_week_theme_he": "שבוע הבהירות — לפשט את המידע הרפואי",
                    "pieces": [
                        {"slot": "push_medication_reminder",
                         "copy_he": "זמן לזריקת Neulasta — סמן/י כשנלקחה ✓"},
                        {"slot": "empty_state_tasks",
                         "copy_he": "אין משימות פתוחות כרגע. כשיתווסף מסמך, המשימות יופיעו כאן."},
                        {"slot": "feature_announcement",
                         "copy_he": "חדש: סיכום מסמכים בעברית פשוטה. העלה/י מסמך רפואי ונפענח אותו →"},
                    ],
                },
            ),
        ]
        s.add_all(demo_runs)
        s.commit()
        print(f"Seeded household {household.id} with user רונית and 4 demo AgentRun drafts.")


if __name__ == "__main__":
    seed()
