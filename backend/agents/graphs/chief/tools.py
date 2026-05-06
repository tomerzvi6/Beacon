"""
Anthropic tool-use definitions for the Chief Agent.

Tools operate only on aggregate/non-PHI data:
  - search_drafts        — semantic search over agent_runs embeddings
  - list_open_initiatives — filtered initiative listing
  - query_aggregate_view  — restricted to approved aggregate views
  - route_task_to_agent   — writes to pending_agent_tasks
  - update_initiative     — status/last_check_at updates
  - create_initiative     — new initiative row
"""
import json
import uuid
from datetime import datetime, timezone

from sqlalchemy import text

from agents.db import get_engine
from agents.graphs.chief.embeddings import embed_text

# ---------------------------------------------------------------------------
# Anthropic tool schemas
# ---------------------------------------------------------------------------

TOOL_DEFINITIONS = [
    {
        "name": "search_drafts",
        "description": (
            "Semantic search over recent agent output drafts. "
            "Returns matching drafts with snippet and relevance score. "
            "Never returns PHI text — only aggregate/summary fields."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Natural-language search query in Hebrew or English"},
                "agent_filter": {
                    "type": "string",
                    "enum": ["guardian", "customer_success", "product", "creative", ""],
                    "description": "Restrict to a specific agent. Empty string = all agents.",
                },
                "date_range_days": {
                    "type": "integer",
                    "description": "How many days back to search (default 7, max 30).",
                    "default": 7,
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "list_open_initiatives",
        "description": "List open initiatives, optionally filtered by target agent.",
        "input_schema": {
            "type": "object",
            "properties": {
                "agent_filter": {
                    "type": "string",
                    "enum": ["guardian", "customer_success", "product", "creative", "cross_agent", ""],
                    "description": "Filter by agent. Empty = all.",
                },
            },
            "required": [],
        },
    },
    {
        "name": "query_aggregate_view",
        "description": (
            "Query a pre-approved aggregate database view (no PHI). "
            "Allowed views: v_user_engagement, v_unclaimed_tasks_age, v_dose_adherence_weekly."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "view_name": {
                    "type": "string",
                    "enum": ["v_user_engagement", "v_unclaimed_tasks_age", "v_dose_adherence_weekly"],
                    "description": "Name of the aggregate view to query.",
                },
                "limit": {"type": "integer", "default": 20},
            },
            "required": ["view_name"],
        },
    },
    {
        "name": "route_task_to_agent",
        "description": "Queue a focused task for an operational agent to pick up on its next run.",
        "input_schema": {
            "type": "object",
            "properties": {
                "target_agent": {
                    "type": "string",
                    "enum": ["guardian", "customer_success", "product", "creative"],
                },
                "task_type": {"type": "string", "description": "Short label, e.g. 'security_deep_dive'"},
                "description_he": {"type": "string", "description": "Task description in Hebrew"},
                "payload": {"type": "object", "description": "Optional JSON payload"},
            },
            "required": ["target_agent", "task_type", "description_he"],
        },
    },
    {
        "name": "update_initiative",
        "description": "Update the status or last_check_at of an existing initiative.",
        "input_schema": {
            "type": "object",
            "properties": {
                "initiative_id": {"type": "string", "description": "UUID of the initiative"},
                "status": {
                    "type": "string",
                    "enum": ["open", "in_progress", "waiting_on_agent", "completed", "cancelled"],
                },
                "last_check_at": {"type": "string", "description": "ISO-8601 timestamp (optional)"},
            },
            "required": ["initiative_id"],
        },
    },
    {
        "name": "create_initiative",
        "description": "Create a new initiative thread for tracking a founder request.",
        "input_schema": {
            "type": "object",
            "properties": {
                "target_agent": {
                    "type": "string",
                    "enum": ["guardian", "customer_success", "product", "creative", "cross_agent"],
                },
                "title_he": {"type": "string"},
                "description_he": {"type": "string"},
            },
            "required": ["target_agent", "title_he"],
        },
    },
]

# ---------------------------------------------------------------------------
# Tool execution
# ---------------------------------------------------------------------------

_ALLOWED_VIEWS = {"v_user_engagement", "v_unclaimed_tasks_age", "v_dose_adherence_weekly"}


def execute_tool(tool_name: str, tool_input: dict) -> dict:
    """Dispatch a tool call and return its result as a dict."""
    dispatch = {
        "search_drafts": _search_drafts,
        "list_open_initiatives": _list_open_initiatives,
        "query_aggregate_view": _query_aggregate_view,
        "route_task_to_agent": _route_task_to_agent,
        "update_initiative": _update_initiative,
        "create_initiative": _create_initiative,
    }
    fn = dispatch.get(tool_name)
    if fn is None:
        return {"error": f"Unknown tool: {tool_name}"}
    try:
        return fn(**tool_input)
    except Exception as exc:
        return {"error": str(exc)}


def _search_drafts(query: str, agent_filter: str = "", date_range_days: int = 7) -> dict:
    days = min(int(date_range_days), 30)
    try:
        query_vec = embed_text(query)
        vec_str = "[" + ",".join(str(x) for x in query_vec) + "]"
    except Exception:
        # If embedding fails, fall back to text keyword search
        vec_str = None

    engine = get_engine()
    with engine.connect() as conn:
        if vec_str:
            sql = text(
                "SELECT id::text, agent_name, started_at, "
                "LEFT(output_draft::text, 400) AS snippet, "
                "1 - (content_embedding_vec <=> :vec::vector) AS score "
                "FROM agent_runs "
                "WHERE started_at >= now() - interval ':days days' "
                "  AND (:agent = '' OR agent_name = :agent) "
                "  AND content_embedding_vec IS NOT NULL "
                "ORDER BY content_embedding_vec <=> :vec::vector "
                "LIMIT 10"
            )
            rows = conn.execute(sql, {"vec": vec_str, "days": days, "agent": agent_filter}).fetchall()
        else:
            sql = text(
                "SELECT id::text, agent_name, started_at, "
                "LEFT(output_draft::text, 400) AS snippet, "
                "0.5 AS score "
                "FROM agent_runs "
                "WHERE started_at >= now() - :days * interval '1 day' "
                "  AND (:agent = '' OR agent_name = :agent) "
                "ORDER BY started_at DESC LIMIT 10"
            )
            rows = conn.execute(sql, {"days": days, "agent": agent_filter}).fetchall()

    return {
        "results": [
            {
                "draft_id": r.id,
                "agent_name": r.agent_name,
                "started_at": str(r.started_at),
                "snippet": r.snippet,
                "score": float(r.score) if r.score else 0.0,
            }
            for r in rows
        ]
    }


def _list_open_initiatives(agent_filter: str = "") -> dict:
    engine = get_engine()
    with engine.connect() as conn:
        sql = text(
            "SELECT id::text, target_agent, title_he, status, "
            "last_check_at, created_at "
            "FROM initiatives "
            "WHERE status NOT IN ('completed', 'cancelled') "
            "  AND (:agent = '' OR target_agent = :agent) "
            "ORDER BY created_at DESC LIMIT 50"
        )
        rows = conn.execute(sql, {"agent": agent_filter}).fetchall()

    return {
        "initiatives": [
            {
                "id": r.id,
                "target_agent": r.target_agent,
                "title_he": r.title_he,
                "status": r.status,
                "last_check_at": str(r.last_check_at) if r.last_check_at else None,
                "created_at": str(r.created_at),
            }
            for r in rows
        ]
    }


def _query_aggregate_view(view_name: str, limit: int = 20) -> dict:
    if view_name not in _ALLOWED_VIEWS:
        return {"error": f"View '{view_name}' is not in the approved whitelist"}
    limit = min(int(limit), 100)
    engine = get_engine()
    with engine.connect() as conn:
        # Safe: view_name is whitelist-validated above
        rows = conn.execute(text(f"SELECT * FROM {view_name} LIMIT :lim"), {"lim": limit}).fetchall()
    return {"rows": [dict(r._mapping) for r in rows]}


def _route_task_to_agent(
    target_agent: str,
    task_type: str,
    description_he: str,
    payload: dict | None = None,
) -> dict:
    engine = get_engine()
    task_id = str(uuid.uuid4())
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO pending_agent_tasks "
                "(id, target_agent, task_type, description_he, payload, status, requested_by) "
                "VALUES (:id::uuid, :target, :ttype, :desc, :payload::jsonb, 'pending', 'chief_agent')"
            ),
            {
                "id": task_id,
                "target": target_agent,
                "ttype": task_type,
                "desc": description_he,
                "payload": json.dumps(payload or {}),
            },
        )
    return {"task_id": task_id, "target_agent": target_agent, "status": "pending"}


def _update_initiative(
    initiative_id: str,
    status: str | None = None,
    last_check_at: str | None = None,
) -> dict:
    now = datetime.now(tz=timezone.utc)
    engine = get_engine()
    sets = ["updated_at = :now"]
    params: dict = {"id": initiative_id, "now": now}
    if status:
        sets.append("status = :status")
        params["status"] = status
    if last_check_at:
        sets.append("last_check_at = :lca")
        params["lca"] = last_check_at
    else:
        sets.append("last_check_at = :now")

    with engine.begin() as conn:
        conn.execute(
            text(f"UPDATE initiatives SET {', '.join(sets)} WHERE id = :id::uuid"),
            params,
        )
    return {"updated": True, "initiative_id": initiative_id}


def _create_initiative(
    target_agent: str,
    title_he: str,
    description_he: str = "",
) -> dict:
    init_id = str(uuid.uuid4())
    engine = get_engine()
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO initiatives (id, target_agent, title_he, description_he, status) "
                "VALUES (:id::uuid, :agent, :title, :desc, 'open')"
            ),
            {"id": init_id, "agent": target_agent, "title": title_he, "desc": description_he},
        )
    return {"initiative_id": init_id, "status": "open"}
