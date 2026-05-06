# Local Development Setup (No Docker)

## Prerequisites

1. **Python 3.11+** — installed and in PATH
2. **PostgreSQL 16** — running locally on `localhost:5432`
   - Windows: Download from https://www.postgresql.org/download/windows/ or use WSL
   - After install, create a user and database:
     ```bash
     createuser -P beacon  # password: beacon_dev (or your choice)
     createdb -O beacon beacon
     ```

## Setup

### 1. Create Python environments

```bash
cd backend

# Parser API
python -m venv venv_parser
source venv_parser/bin/activate  # or venv_parser\Scripts\activate on Windows
pip install -e ./parser_api
pip install -e ./shared

# Agents
python -m venv venv_agents
source venv_agents/bin/activate
pip install -e ./agents
pip install -e ./shared
```

### 2. Set up the database

```bash
# Still in backend/, with venv activated

# Run Alembic migrations
export DATABASE_URL="postgresql+psycopg://beacon:beacon_dev@localhost:5432/beacon"
alembic -c alembic.ini upgrade head

# Create roles and views (as Postgres superuser)
psql -U postgres -d beacon -f shared/roles.sql

# Seed demo data
python -m shared.seed
```

### 3. Run the services

**Terminal 1 — Parser API:**
```bash
source venv_parser/bin/activate
export DATABASE_URL="postgresql+psycopg://beacon:beacon_dev@localhost:5432/beacon"
export ANTHROPIC_API_KEY="sk-..."  # your actual key
# Storage backend — local disk by default (Phase 8)
export STORAGE_BACKEND=local          # or "s3" for production
export LOCAL_UPLOAD_DIR=./uploads     # where local uploads are stored
export LOCAL_API_BASE_URL=http://localhost:8000
uvicorn parser_api.main:app --reload --port 8000
```

**Terminal 2 — Streamlit Dashboard:**
```bash
source venv_agents/bin/activate
export DATABASE_URL="postgresql+psycopg://beacon:beacon_dev@localhost:5432/beacon"
streamlit run agents/dashboard.py --logger.level=info --server.port=8501
```

**Terminal 3 — Scheduler:**
```bash
source venv_agents/bin/activate
export DATABASE_URL="postgresql+psycopg://beacon:beacon_dev@localhost:5432/beacon"
export ANTHROPIC_API_KEY="sk-..."
# Optional overrides (defaults shown):
# export GUARDIAN_HOUR=7        # daily 07:00
# export CS_PROACTIVE_HOUR=9    # daily 09:00
python agents/scheduler.py
```

### Agents (Phase 7)

| Agent | File | Cadence | Draft type |
|---|---|---|---|
| Guardian | `agents/graphs/guardian/graph.py` | Daily 07:00 | `security_brief` |
| Customer Success | `agents/graphs/customer_success.py` | Daily 09:00 (proactive) + 30 min (reactive) | `push`, `support_reply`, `cs_daily_brief` |
| Product | `agents/graphs/product.py` | Sunday 08:00 | `product_report` |
| Creative | `agents/graphs/creative/graph.py` | Sunday 10:00 + on-demand | `content_draft` |

Run an agent manually (for testing):
```bash
python -c "from agents.graphs import run_guardian; run_guardian()"
python -c "from agents.graphs import run_customer_success_proactive; run_customer_success_proactive()"
python -c "from agents.graphs import run_product; run_product()"
python -c "from agents.graphs import run_creative_weekly; run_creative_weekly()"
```

## Stopping & restarting

- Kill each `venv` terminal with `Ctrl+C`.
- To reset the DB: `dropdb beacon && createdb -O beacon beacon && alembic upgrade head && python -m shared.seed`.

## Phase 8 — Document Upload API

### New endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/v1/uploads/presign` | Generate upload URL. Body: `{mime_type, category?, is_private?, filename?}` |
| `PUT` | `/v1/uploads/local/{document_id}` | Local-dev only — receive raw file bytes |
| `POST` | `/v1/uploads/finalize` | Record SHA-256 hash; returns `409` on duplicate |
| `POST` | `/v1/uploads/finalize/batch` | Finalize up to 15 documents at once |
| `GET` | `/v1/documents/` | List documents (filters: category, date range, q, uploaded_by, cursor) |
| `DELETE` | `/v1/documents/{id}` | Soft delete |
| `GET` | `/v1/documents/trash` | Soft-deleted documents (patient/co_owner only) |
| `POST` | `/v1/documents/{id}/restore` | Restore from trash |
| `PATCH` | `/v1/documents/{id}` | Update category, is_private, filename |
| `PATCH` | `/v1/tasks/{id}` | Edit task (audit trail in edit_history JSONB) |
| `GET` | `/v1/households/members` | List household members |
| `POST` | `/v1/households/invite/co-owner` | Create targeted co-owner invite |
| `POST` | `/v1/households/invite/accept` | Accept co-owner invite with 6-digit code |
| `POST` | `/v1/households/caregiver-invite` | Create open caregiver invite |
| `POST` | `/v1/households/join` | Join as caregiver with 6-digit code |

### Local upload flow (dev)

```
1. POST /v1/uploads/presign  →  { document_id, upload_url, expires_in_seconds }
2. PUT  <upload_url>          →  raw file bytes (upload_url = http://localhost:8000/v1/uploads/local/{id})
3. POST /v1/uploads/finalize  →  { document_id, status: "ok"|"conflict", ... }
4. POST /v1/documents/{id}/parse
```

### Hard delete

Documents soft-deleted for **30+ days** are permanently purged daily at **03:00** by the scheduler job `job_hard_delete`. Storage objects are deleted first.

### Invite code TTL

Default: 7 days (10 080 minutes). Override with `INVITE_CODE_TTL_MINUTES`.

## Phase 9.5 — Chief Agent (Beacon Brain)

### What it is

The Chief Agent is a meta-orchestrator that sits above the four operational agents.
It synthesises their outputs into a daily brief and provides a conversational chat
interface for the founder. PHI isolation is the same as the four operational agents —
the Chief never reads `tasks.title_he`, `documents.parsed_summary_he`, or
`symptom_reports.note_he`.

### New scheduler job

`job_chief_brief` runs daily at **11:00** (after all four operational agents).
Override: `export CHIEF_AGENT_HOUR=11`

### Running the chief brief manually

```bash
source venv_agents/bin/activate
export DATABASE_URL="postgresql+psycopg://beacon:beacon_dev@localhost:5432/beacon"
export ANTHROPIC_API_KEY="sk-..."
# Optional — defaults to Voyage AI
export EMBEDDING_PROVIDER=voyage       # or "openai"
export VOYAGE_API_KEY="pa-..."         # if using Voyage
python -c "from agents.graphs.chief.briefs import generate_daily_brief; print(generate_daily_brief())"
```

The Chief tab in the Streamlit dashboard also has a "Generate now" button.

### Backfilling embeddings

After running migration 005, embed all existing `agent_runs` rows:

```bash
source venv_agents/bin/activate
export DATABASE_URL="..."
export ANTHROPIC_API_KEY="sk-..."
export EMBEDDING_PROVIDER=voyage       # or openai
export VOYAGE_API_KEY="pa-..."

# Dry run first
python -m agents.tools.backfill_embeddings --dry-run

# Full backfill (batch of 20 rows at a time)
python -m agents.tools.backfill_embeddings --batch-size 20

# Backfill only the first 100 rows
python -m agents.tools.backfill_embeddings --limit 100
```

### How task routing works

The Chief Agent can queue tasks for operational agents via the `route_task_to_agent`
tool. This writes a row to `pending_agent_tasks`. On the next scheduled run, each
agent's `process_pending_tasks` entry node picks up the row, runs a focused Claude
call, creates an `AgentRun` with the result, and marks the task `completed`.

Flow:
```
Chief writes pending_agent_tasks row
    ↓
Agent's next scheduled run starts
    ↓
process_pending_tasks node picks up row, marks picked_up_at
    ↓
Claude generates focused output (creates AgentRun)
    ↓
Task marked completed with result_draft_id
    ↓
Founder reviews AgentRun in HITL dashboard (Inbox tab)
```

### Testing PHI isolation

The Chief Agent's tool whitelist prevents any access to PHI columns. To verify:

```bash
python -c "
from agents.graphs.chief.tools import _query_aggregate_view
# This must return an error — 'tasks' is not in the approved view whitelist
result = _query_aggregate_view('tasks')
assert 'error' in result, f'PHI isolation FAILED: {result}'
print('PHI isolation OK:', result)
"
```

### Embedding provider config

| Env var | Default | Description |
|---|---|---|
| `EMBEDDING_PROVIDER` | `voyage` | `voyage` or `openai` |
| `EMBEDDING_MODEL` | `voyage-2` | Model name |
| `VOYAGE_API_KEY` | _(empty)_ | Voyage AI API key |
| `OPENAI_API_KEY` | _(empty)_ | OpenAI API key (fallback) |
| `CHIEF_BRIEF_MAX_DRAFTS` | `50` | Max drafts to include in brief |
| `CHIEF_AGENT_HOUR` | `11` | Hour (0-23) for daily brief cron |

### Agents table (updated)

| Agent | File | Cadence | Draft type |
|---|---|---|---|
| **Chief** | `agents/graphs/chief/` | Daily 11:00 | `chief_brief` in DB |
| Guardian | `agents/graphs/guardian/graph.py` | Daily 07:00 | `security_brief` |
| Customer Success | `agents/graphs/customer_success.py` | Daily 09:00 (proactive) + 30 min (reactive) | `push`, `support_reply`, `cs_daily_brief` |
| Product | `agents/graphs/product.py` | Sunday 08:00 | `product_report` |
| Creative | `agents/graphs/creative/graph.py` | Sunday 10:00 + on-demand | `content_draft` |

## Notes

- Set `DATABASE_URL` to match your local Postgres credentials.
- Secrets (API keys, etc.) go in `.env` or environment variables — **never commit them**.
