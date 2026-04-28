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

**Terminal 3 — Scheduler (when Phase 4 is ready):**
```bash
source venv_agents/bin/activate
export DATABASE_URL="postgresql+psycopg://beacon:beacon_dev@localhost:5432/beacon"
python agents/scheduler.py
```

## Stopping & restarting

- Kill each `venv` terminal with `Ctrl+C`.
- To reset the DB: `dropdb beacon && createdb -O beacon beacon && alembic upgrade head && python -m shared.seed`.

## Notes

- Set `DATABASE_URL` to match your local Postgres credentials.
- Secrets (API keys, etc.) go in `.env` or environment variables — **never commit them**.
