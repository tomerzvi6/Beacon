"""
Shared utility: process_pending_tasks_for_agent()

Each operational agent calls this at graph entry. It:
  1. Queries pending_agent_tasks for this agent
  2. Marks each as picked_up
  3. Uses Claude to produce a focused output based on the task description
  4. Creates an AgentRun row for the result
  5. Marks the task completed with result_draft_id

Returns the count of tasks processed (not an agent state — callers use it as a
passthrough node that mutates the DB as a side-effect).
"""
import json
import logging
import uuid
from datetime import datetime, timezone

from anthropic import Anthropic
from sqlalchemy import text
from sqlalchemy.orm import Session

from agents.db import get_engine
from shared.models import AgentRun

log = logging.getLogger("beacon.pending_tasks")


def process_pending_tasks_for_agent(agent_name: str) -> int:
    """
    Process all pending tasks queued for *agent_name* by the Chief Agent.
    Returns the number of tasks processed.
    """
    engine = get_engine()
    with engine.connect() as conn:
        tasks = conn.execute(
            text(
                "SELECT id::text, task_type, description_he, payload "
                "FROM pending_agent_tasks "
                "WHERE target_agent = :agent AND status = 'pending' "
                "ORDER BY created_at ASC LIMIT 10"
            ),
            {"agent": agent_name},
        ).fetchall()

    if not tasks:
        return 0

    client = Anthropic()
    processed = 0

    for task in tasks:
        task_id = task.id
        try:
            # Mark as picked up
            with engine.begin() as conn:
                conn.execute(
                    text(
                        "UPDATE pending_agent_tasks SET status = 'picked_up', picked_up_at = :ts "
                        "WHERE id = :id::uuid"
                    ),
                    {"ts": datetime.now(tz=timezone.utc), "id": task_id},
                )

            payload = task.payload or {}
            payload_str = json.dumps(payload, ensure_ascii=False) if payload else ""

            # Ask Claude to handle the focused task within the agent's domain
            resp = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=800,
                system=[{
                    "type": "text",
                    "text": (
                        f"אתה הסוכן {agent_name} של מערכת Beacon. "
                        "קיבלת משימה ממנהל הסוכנים הראשי. "
                        "ענה בעברית, קצר ומדויק. אל תכלול PHI."
                    ),
                    "cache_control": {"type": "ephemeral"},
                }],
                messages=[{
                    "role": "user",
                    "content": (
                        f"סוג משימה: {task.task_type}\n\n"
                        f"תיאור: {task.description_he}\n\n"
                        + (f"פרמטרים: {payload_str}" if payload_str else "")
                    ),
                }],
            )
            result_text = resp.content[0].text if resp.content else ""

            # Create an AgentRun row for the focused result
            run = AgentRun(
                agent_name=agent_name,
                status="awaiting_approval",
                input_summary={
                    "source": "chief_agent_task",
                    "task_id": task_id,
                    "task_type": task.task_type,
                },
                output_draft={
                    "type": "chief_task_result",
                    "task_type": task.task_type,
                    "description_he": task.description_he,
                    "result_he": result_text,
                },
            )
            with Session(engine) as session:
                session.add(run)
                session.commit()
                run_id = str(run.id)

            # Mark task completed
            with engine.begin() as conn:
                conn.execute(
                    text(
                        "UPDATE pending_agent_tasks "
                        "SET status = 'completed', completed_at = :ts, result_draft_id = :rid::uuid "
                        "WHERE id = :id::uuid"
                    ),
                    {
                        "ts": datetime.now(tz=timezone.utc),
                        "rid": run_id,
                        "id": task_id,
                    },
                )

            processed += 1
            log.info("[%s] Processed Chief task %s → run_id %s", agent_name, task_id, run_id)

        except Exception as exc:
            log.exception("[%s] Failed to process Chief task %s: %s", agent_name, task_id, exc)
            with engine.begin() as conn:
                conn.execute(
                    text(
                        "UPDATE pending_agent_tasks SET status = 'failed' WHERE id = :id::uuid"
                    ),
                    {"id": task_id},
                )

    return processed
