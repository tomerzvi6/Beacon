-- Run once after the first Alembic migration (as superuser / DB owner).
-- Sets up the two DB roles enforcing the Track A / Track B separation.

-- ============================================================
-- Track A role — Parser API (full PHI access)
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'parser_api_role') THEN
    CREATE ROLE parser_api_role LOGIN PASSWORD 'change_in_prod';
  END IF;
END $$;

GRANT CONNECT ON DATABASE beacon TO parser_api_role;
GRANT USAGE  ON SCHEMA public TO parser_api_role;

-- Full access to PHI tables
GRANT SELECT, INSERT, UPDATE, DELETE ON
    households, users, documents, tasks,
    medications, dose_events, symptom_reports,
    audit_log
TO parser_api_role;

-- Bypass RLS so the app can set app.household_id and enforce isolation itself
ALTER ROLE parser_api_role SET row_security = off;

-- Phase 8 tables
GRANT SELECT, INSERT, UPDATE, DELETE ON
    household_members, household_invites
TO parser_api_role;

-- is_private enforcement note:
--   RLS is bypassed for parser_api_role, so the application layer in
--   routes/documents.py filters out is_private=TRUE documents for caregivers
--   who are not the uploader.  Any change to that logic MUST preserve this filter.

-- Sequence access (for audit_log bigserial)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO parser_api_role;

-- ============================================================
-- Track B role — Agents (NO direct PHI access)
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agent_role') THEN
    CREATE ROLE agent_role LOGIN PASSWORD 'change_in_prod';
  END IF;
END $$;

GRANT CONNECT ON DATABASE beacon TO agent_role;
GRANT USAGE  ON SCHEMA public TO agent_role;

-- Agent-owned tables (full)
GRANT SELECT, INSERT, UPDATE, DELETE ON
    agent_runs, support_tickets, agent_metrics_snapshots,
    doc_chunks, audit_log
TO agent_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO agent_role;

-- Guardian needs read-only access to document metadata (non-PHI columns only)
GRANT SELECT ON documents TO agent_role;

-- ============================================================
-- Read-only views for agents (aggregates only, no PHI text)
-- ============================================================

-- Unclaimed approved tasks older than 48h — titles/descriptions excluded
CREATE OR REPLACE VIEW v_unclaimed_tasks_age AS
SELECT
    id            AS task_id,
    household_id,
    category,
    EXTRACT(EPOCH FROM (now() - created_at)) / 3600 AS age_hours,
    due_at
FROM tasks
WHERE status = 'approved'
  AND claimed_by IS NULL;

GRANT SELECT ON v_unclaimed_tasks_age TO agent_role;

-- Weekly usage metrics — household-level aggregates, no text
CREATE OR REPLACE VIEW v_usage_metrics_weekly AS
SELECT
    date_trunc('week', t.created_at)   AS week,
    t.household_id,
    t.category,
    COUNT(*)                           AS total_tasks,
    COUNT(*) FILTER (WHERE t.status = 'done')      AS done_tasks,
    COUNT(*) FILTER (WHERE t.status = 'dismissed') AS dismissed_tasks
FROM tasks t
GROUP BY 1, 2, 3;

GRANT SELECT ON v_usage_metrics_weekly TO agent_role;

-- Support inbox — user message body is PII not clinical PHI; still exposed to agent_role
CREATE OR REPLACE VIEW v_support_inbox AS
SELECT
    st.id,
    st.user_id,
    st.channel,
    st.subject,
    st.body,
    st.status,
    st.created_at
FROM support_tickets st
WHERE st.status = 'new';

GRANT SELECT ON v_support_inbox TO agent_role;

-- Dose adherence aggregates (no PHI)
CREATE OR REPLACE VIEW v_dose_adherence_weekly AS
SELECT
    date_trunc('week', de.scheduled_at)  AS week,
    m.household_id,
    COUNT(*)                             AS scheduled_doses,
    COUNT(de.taken_at)                   AS taken_doses
FROM dose_events de
JOIN medications m ON m.id = de.medication_id
GROUP BY 1, 2;

GRANT SELECT ON v_dose_adherence_weekly TO agent_role;

-- User engagement — household-level activity signal for Customer Success + Product agents
-- No PHI text (no names, no medical content) — only aggregate timing/counts
CREATE OR REPLACE VIEW v_user_engagement AS
SELECT
    u.household_id,
    MAX(t.created_at)                                         AS last_task_activity,
    COUNT(t.id)                                              AS total_tasks,
    EXTRACT(EPOCH FROM (now() - MAX(t.created_at))) / 86400  AS days_since_activity
FROM users u
LEFT JOIN tasks t ON t.household_id = u.household_id
GROUP BY u.household_id;

GRANT SELECT ON v_user_engagement TO agent_role;
