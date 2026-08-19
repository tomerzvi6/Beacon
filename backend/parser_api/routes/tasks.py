"""Task management."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, get_user_context
from shared.models import AuditLog, Task
from shared.schemas import TaskCreateIn, TaskOut, TaskPatchIn

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
        .filter(
            Task.household_id == uuid.UUID(user.household_id),
            Task.status == status_filter,
        )
        .order_by(Task.created_at.desc())
        .all()
    )
    return [TaskOut.model_validate(t) for t in tasks]


@router.post("/", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
def create_task(
    body: TaskCreateIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """Family member creates a task directly (mirrors DailyTask) — no
    suggested→approve step since there's no AI draft behind it."""
    now = datetime.now(tz=timezone.utc)
    task = Task(
        id=uuid.uuid4(),
        household_id=uuid.UUID(user.household_id),
        title_he=body.title_he,
        description_he=body.description_he,
        category=body.category,
        kind=body.kind,
        origin="manual",
        due_at=body.due_at,
        status="approved",
        approved_by=uuid.UUID(user.user_id),
        approved_at=now,
        created_at=now,
        edited_by_user=False,
        edit_history=[],
    )
    session.add(task)
    session.commit()
    return TaskOut.model_validate(task)


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
    task = session.query(Task).filter(
        Task.id == task_id,
        Task.household_id == uuid.UUID(user.household_id),
    ).first()
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


@router.patch("/{task_id}", response_model=TaskOut)
def patch_task(
    task_id: str,
    body: TaskPatchIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """Edit a task's title/description/due date; captures audit trail in edit_history."""
    task = session.query(Task).filter(
        Task.id == task_id,
        Task.household_id == uuid.UUID(user.household_id),
    ).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    if task.status == "suggested":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Approve task before editing",
        )

    # Capture original text once (never overwritten after first edit)
    if task.original_text is None and task.title_he:
        task.original_text = task.title_he

    history_entry: dict = {"edited_at": datetime.now(tz=timezone.utc).isoformat(), "by": user.user_id}
    if body.title_he is not None:
        history_entry["old_title_he"] = task.title_he
        task.title_he = body.title_he
        task.edited_by_user = True
    if body.description_he is not None:
        history_entry["old_description_he"] = task.description_he
        task.description_he = body.description_he
    if body.due_at is not None:
        history_entry["old_due_at"] = task.due_at.isoformat() if task.due_at else None
        task.due_at = body.due_at

    # Append to JSONB array
    current_history = list(task.edit_history or [])
    current_history.append(history_entry)
    task.edit_history = current_history

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="edit_task",
            target_table="tasks",
            target_id=task.id,
            household_id=task.household_id,
            metadata_=history_entry,
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
    task = session.query(Task).filter(
        Task.id == task_id,
        Task.household_id == uuid.UUID(user.household_id),
    ).first()
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


@router.post("/{task_id}/complete", response_model=TaskOut)
def complete_task(
    task_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """Mark a task done (mirrors DailyTask.isCompleted)."""
    task = session.query(Task).filter(
        Task.id == task_id,
        Task.household_id == uuid.UUID(user.household_id),
    ).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    task.status = "done"
    task.completed_at = datetime.now(tz=timezone.utc)
    session.commit()

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="complete_task",
            target_table="tasks",
            target_id=task.id,
            household_id=task.household_id,
        )
    )
    session.commit()

    return TaskOut.model_validate(task)


@router.post("/{task_id}/dismiss", response_model=TaskOut)
def dismiss_task(
    task_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """Dismiss a suggested/approved task without completing it."""
    task = session.query(Task).filter(
        Task.id == task_id,
        Task.household_id == uuid.UUID(user.household_id),
    ).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    task.status = "dismissed"
    session.commit()

    session.add(
        AuditLog(
            actor_type="parser_api",
            actor_id=user.user_id,
            action="dismiss_task",
            target_table="tasks",
            target_id=task.id,
            household_id=task.household_id,
        )
    )
    session.commit()

    return TaskOut.model_validate(task)


@router.post("/{task_id}/unclaim", response_model=TaskOut)
def unclaim_task(
    task_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """Release a claimed task back to the household pool."""
    task = session.query(Task).filter(
        Task.id == task_id,
        Task.household_id == uuid.UUID(user.household_id),
    ).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    task.claimed_by = None
    task.claimed_at = None
    session.commit()
    return TaskOut.model_validate(task)


@router.post("/{task_id}/reopen", response_model=TaskOut)
def reopen_task(
    task_id: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(get_user_context),
) -> TaskOut:
    """Undo a completion (mirrors DailyTask.isCompleted toggling back off)."""
    task = session.query(Task).filter(
        Task.id == task_id,
        Task.household_id == uuid.UUID(user.household_id),
    ).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    task.status = "approved"
    task.completed_at = None
    session.commit()
    return TaskOut.model_validate(task)
