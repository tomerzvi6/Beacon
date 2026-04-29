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

## Notes

- Set `DATABASE_URL` to match your local Postgres credentials.
- Secrets (API keys, etc.) go in `.env` or environment variables — **never commit them**.
