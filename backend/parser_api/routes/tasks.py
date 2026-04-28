"""Task management."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import AuditLog, Task
from shared.schemas import TaskOut

router = APIRouter(prefix="/v1/tasks", tags=["tasks"])


@router.get("/", response_model=list[TaskOut])
def list_tasks(
    status_filter: str = "approved",
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> list[TaskOut]:
    """List tasks for the user's household, filtered by status."""
    tasks = (
        session.query(Task)
        .filter(Task.status == status_filter)
        .order_by(Task.created_at.desc())
        .all()
    )
    return [TaskOut.model_validate(t) for t in tasks]


@router.post("/{task_id}/approve", response_model=TaskOut)
def approve_task(
    task_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """
    User approves a suggested task.
    Only user-approved tasks can be claimed or nudged by agents.
    """
    task = session.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    if task.status != "suggested":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Can only approve suggested tasks",
        )

    task.status = "approved"
    task.approved_by = uuid.UUID(user.user_id)
    task.approved_at = datetime.now(tz=timezone.utc)
    session.commit()

    # Audit
    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="approve_task",
            target_table="tasks",
            target_id=task.id,
            household_id=task.household_id,
        )
    )
    session.commit()

    return TaskOut.model_validate(task)


@router.post("/{task_id}/claim", response_model=TaskOut)
def claim_task(
    task_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """User claims ownership of a task (mirrors 'קח על עצמך משימה')."""
    task = session.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    task.claimed_by = uuid.UUID(user.user_id)
    task.claimed_at = datetime.now(tz=timezone.utc)
    session.commit()

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="claim_task",
            target_table="tasks",
            target_id=task.id,
            household_id=task.household_id,
        )
    )
    session.commit()

    return TaskOut.model_validate(task)
