"""Family support feed (פיד)."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from parser_api.auth import TokenPayload
from parser_api.dependencies import get_session, require_module_access
from parser_api.services.notify import notify_household
from shared.models import FeedComment, FeedPost, FeedReaction
from shared.schemas import (
    FeedCommentIn,
    FeedCommentOut,
    FeedPostIn,
    FeedPostOut,
    FeedReactionIn,
)

router = APIRouter(prefix="/v1/feed", tags=["feed"])


def _to_out(post: FeedPost, viewer_user_id: uuid.UUID) -> FeedPostOut:
    heart_count = sum(1 for r in post.reactions if r.reaction == "heart")
    hug_count = sum(1 for r in post.reactions if r.reaction == "hug")
    my_reactions = [r.reaction for r in post.reactions if r.user_id == viewer_user_id]
    return FeedPostOut(
        id=post.id,
        author_user_id=post.author_user_id,
        body=post.body,
        status=post.status,
        audience=post.audience,
        posted_at=post.posted_at,
        heart_count=heart_count,
        hug_count=hug_count,
        my_reactions=my_reactions,
        comments=[FeedCommentOut.model_validate(c) for c in post.comments],
    )


@router.get("/", response_model=list[FeedPostOut])
def list_posts(
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_module_access("feed", 1)),
) -> list[FeedPostOut]:
    posts = session.scalars(
        select(FeedPost)
        .where(FeedPost.household_id == uuid.UUID(user.household_id))
        .options(selectinload(FeedPost.comments), selectinload(FeedPost.reactions))
        .order_by(FeedPost.posted_at.desc())
    ).all()
    viewer = uuid.UUID(user.user_id)
    return [_to_out(p, viewer) for p in posts]


@router.post("/", response_model=FeedPostOut, status_code=status.HTTP_201_CREATED)
def create_post(
    body: FeedPostIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_module_access("feed", 2)),
) -> FeedPostOut:
    # id/posted_at set explicitly — see schedule.py's create_event for why.
    post = FeedPost(
        id=uuid.uuid4(),
        household_id=uuid.UUID(user.household_id),
        author_user_id=uuid.UUID(user.user_id),
        body=body.body,
        status=body.status,
        audience=body.audience,
        posted_at=datetime.now(tz=timezone.utc),
    )
    session.add(post)
    session.commit()

    notify_household(
        session, post.household_id,
        title="עדכון חדש במעגל התמיכה",
        body=body.body[:120],
        exclude_user_id=post.author_user_id,
    )

    return _to_out(post, uuid.UUID(user.user_id))


def _get_post(session: Session, post_id: str, household_id: str) -> FeedPost:
    post = session.scalar(
        select(FeedPost)
        .where(FeedPost.id == post_id, FeedPost.household_id == uuid.UUID(household_id))
        .options(selectinload(FeedPost.comments), selectinload(FeedPost.reactions))
    )
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
    return post


@router.post("/{post_id}/comments", response_model=FeedPostOut, status_code=status.HTTP_201_CREATED)
def add_comment(
    post_id: str,
    body: FeedCommentIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_module_access("feed", 2)),
) -> FeedPostOut:
    post = _get_post(session, post_id, user.household_id)
    comment = FeedComment(
        id=uuid.uuid4(),
        post_id=post.id,
        author_user_id=uuid.UUID(user.user_id),
        body=body.body,
        posted_at=datetime.now(tz=timezone.utc),
    )
    session.add(comment)
    session.commit()
    session.refresh(post)
    return _to_out(post, uuid.UUID(user.user_id))


@router.post("/{post_id}/react", response_model=FeedPostOut)
def react_to_post(
    post_id: str,
    body: FeedReactionIn,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_module_access("feed", 2)),
) -> FeedPostOut:
    post = _get_post(session, post_id, user.household_id)
    try:
        with session.begin_nested():
            session.add(FeedReaction(
                id=uuid.uuid4(),
                post_id=post.id,
                user_id=uuid.UUID(user.user_id),
                reaction=body.reaction,
                created_at=datetime.now(tz=timezone.utc),
            ))
    except IntegrityError:
        pass  # already reacted this way — idempotent tap
    session.commit()
    session.refresh(post)
    return _to_out(post, uuid.UUID(user.user_id))


@router.delete("/{post_id}/react", response_model=FeedPostOut)
def remove_reaction(
    post_id: str,
    reaction: str,
    session: Session = Depends(get_session),
    user: TokenPayload = Depends(require_module_access("feed", 2)),
) -> FeedPostOut:
    post = _get_post(session, post_id, user.household_id)
    existing = session.scalar(
        select(FeedReaction).where(
            FeedReaction.post_id == post.id,
            FeedReaction.user_id == uuid.UUID(user.user_id),
            FeedReaction.reaction == reaction,
        )
    )
    if existing:
        session.delete(existing)
        session.commit()
        session.refresh(post)
    return _to_out(post, uuid.UUID(user.user_id))
