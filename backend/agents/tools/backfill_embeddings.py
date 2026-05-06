"""
Embedding backfill CLI.

Computes content_embedding_vec for all agent_runs rows that don't have one yet.
Run once after migration 005:

  python -m agents.tools.backfill_embeddings

Optional flags:
  --batch-size N    rows per DB commit  (default 20)
  --limit N         max rows to process (default: all)
  --dry-run         print counts without writing
"""
import argparse
import json
import logging
import sys

from sqlalchemy import text

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("beacon.backfill_embeddings")


def _text_for_embedding(output_draft: dict) -> str:
    """Convert an output_draft JSONB into a string suitable for embedding."""
    draft_type = output_draft.get("type", "")
    parts = [f"type:{draft_type}"]

    if draft_type == "security_brief":
        parts.append(output_draft.get("markdown", "")[:1000])
    elif draft_type in ("weekly_report", "product_report"):
        parts.append(output_draft.get("markdown", "")[:1000])
    elif draft_type == "content_draft":
        for piece in output_draft.get("pieces", [])[:5]:
            parts.append(piece.get("copy_he", ""))
    elif draft_type == "cs_daily_brief":
        parts.append(output_draft.get("cohort_summary_he", "")[:800])
    elif draft_type in ("push", "support_reply"):
        parts.append(output_draft.get("body_he", ""))
    elif draft_type == "chief_task_result":
        parts.append(output_draft.get("result_he", "")[:800])
    else:
        parts.append(str(output_draft)[:500])

    return " ".join(p for p in parts if p)


def run_backfill(batch_size: int = 20, limit: int = 0, dry_run: bool = False) -> None:
    from agents.db import get_engine
    from agents.graphs.chief.embeddings import embed_text

    engine = get_engine()

    with engine.connect() as conn:
        count_sql = (
            "SELECT COUNT(*) FROM agent_runs WHERE content_embedding_vec IS NULL"
        )
        total = conn.execute(text(count_sql)).scalar()

    if limit:
        total = min(total, limit)

    log.info("Found %d agent_runs rows without embeddings (limit=%s)", total, limit or "none")
    if dry_run:
        log.info("[dry-run] Would process %d rows in batches of %d", total, batch_size)
        return

    processed = 0
    offset = 0

    while processed < total:
        fetch_lim = min(batch_size, total - processed)
        with engine.connect() as conn:
            rows = conn.execute(
                text(
                    "SELECT id::text, output_draft FROM agent_runs "
                    "WHERE content_embedding_vec IS NULL "
                    "ORDER BY started_at ASC LIMIT :lim OFFSET :off"
                ),
                {"lim": fetch_lim, "off": offset},
            ).fetchall()

        if not rows:
            break

        for row in rows:
            try:
                draft = row.output_draft if isinstance(row.output_draft, dict) else json.loads(row.output_draft)
                text_content = _text_for_embedding(draft)
                if not text_content.strip():
                    continue
                vec = embed_text(text_content)
                vec_str = "[" + ",".join(str(x) for x in vec) + "]"

                with engine.begin() as conn:
                    conn.execute(
                        text(
                            "UPDATE agent_runs SET content_embedding_vec = :vec::vector "
                            "WHERE id = :id::uuid"
                        ),
                        {"vec": vec_str, "id": row.id},
                    )
                processed += 1
                if processed % 10 == 0:
                    log.info("Progress: %d/%d", processed, total)
            except Exception as exc:
                log.warning("Failed to embed run %s: %s", row.id, exc)
                processed += 1

        offset += len(rows)

    log.info("Backfill complete. Processed %d rows.", processed)


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill embeddings for agent_runs")
    parser.add_argument("--batch-size", type=int, default=20)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    run_backfill(
        batch_size=args.batch_size,
        limit=args.limit,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
