"""
Chief Agent StateGraph.

Nodes:
  gather_recent_activity   → load last 24h drafts + open initiatives
  retrieve_relevant_context → RAG semantic search (chat mode only)
  synthesize_or_answer      → LLM call with tool_use
  validate_grounding        → every claim must have a citation; retry once if not
  persist_output            → save brief or conversation turn

Mode branching: state["mode"] == "brief" | "chat"
"""
import json
import os
import re

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy import text

from agents.db import get_engine
from agents.graphs.chief.embeddings import embed_text
from agents.graphs.chief.prompts import BRIEF_TEMPLATE, CHAT_TEMPLATE, CHIEF_SYSTEM
from agents.graphs.chief.state import ChiefState
from agents.graphs.chief.tools import TOOL_DEFINITIONS, execute_tool

_MODEL = os.environ.get("CHIEF_AGENT_MODEL", "claude-sonnet-4-6")
_MAX_DRAFTS = int(os.environ.get("CHIEF_BRIEF_MAX_DRAFTS", "50"))


# ---------------------------------------------------------------------------
# Node: gather_recent_activity
# ---------------------------------------------------------------------------

def gather_recent_activity(state: ChiefState) -> ChiefState:
    engine = get_engine()
    with engine.connect() as conn:
        draft_rows = conn.execute(
            text(
                "SELECT id::text AS run_id, agent_name, started_at, "
                "output_draft->>'type' AS draft_type, "
                "LEFT(output_draft::text, 600) AS content_preview "
                "FROM agent_runs "
                "WHERE started_at >= now() - interval '24 hours' "
                "ORDER BY started_at DESC LIMIT :lim"
            ),
            {"lim": _MAX_DRAFTS},
        ).fetchall()

        init_rows = conn.execute(
            text(
                "SELECT id::text, target_agent, title_he, status, last_check_at "
                "FROM initiatives "
                "WHERE status NOT IN ('completed', 'cancelled') "
                "ORDER BY created_at DESC LIMIT 30"
            )
        ).fetchall()

    state["recent_drafts"] = [dict(r._mapping) for r in draft_rows]
    state["open_initiatives"] = [dict(r._mapping) for r in init_rows]
    return state


# ---------------------------------------------------------------------------
# Node: retrieve_relevant_context (RAG — chat mode only)
# ---------------------------------------------------------------------------

def retrieve_relevant_context(state: ChiefState) -> ChiefState:
    if state["mode"] != "chat" or not state["user_query"].strip():
        state["retrieved_context"] = []
        return state

    try:
        vec = embed_text(state["user_query"])
        vec_str = "[" + ",".join(str(x) for x in vec) + "]"
        engine = get_engine()
        with engine.connect() as conn:
            rows = conn.execute(
                text(
                    "SELECT id::text AS run_id, agent_name, "
                    "LEFT(output_draft::text, 500) AS snippet, "
                    "1 - (content_embedding_vec <=> :vec::vector) AS score "
                    "FROM agent_runs "
                    "WHERE content_embedding_vec IS NOT NULL "
                    "  AND started_at >= now() - interval '7 days' "
                    "ORDER BY content_embedding_vec <=> :vec::vector "
                    "LIMIT 5"
                ),
                {"vec": vec_str},
            ).fetchall()
        state["retrieved_context"] = [
            {
                "run_id": r.run_id,
                "agent_name": r.agent_name,
                "snippet": r.snippet,
                "score": float(r.score),
            }
            for r in rows
        ]
    except Exception:
        state["retrieved_context"] = []
    return state


# ---------------------------------------------------------------------------
# Node: synthesize_or_answer
# ---------------------------------------------------------------------------

def synthesize_or_answer(state: ChiefState) -> ChiefState:
    client = Anthropic()

    if state["mode"] == "brief":
        # Build a concise summary of recent drafts per agent
        by_agent: dict[str, list] = {}
        for d in state["recent_drafts"]:
            by_agent.setdefault(d["agent_name"], []).append(d)

        agent_summary_parts = []
        for agent, drafts in by_agent.items():
            agent_summary_parts.append(
                f"**{agent}** ({len(drafts)} drafts): "
                + "; ".join(d.get("draft_type", "?") for d in drafts[:3])
            )
        agent_drafts_summary = "\n".join(agent_summary_parts) or "אין נתונים מ-24 השעות האחרונות."

        init_parts = [
            f"- [{i['status']}] {i['title_he']} ({i['target_agent']})"
            for i in state["open_initiatives"]
        ]
        open_initiatives_summary = "\n".join(init_parts) or "אין יוזמות פתוחות."

        user_content = BRIEF_TEMPLATE.format(
            agent_drafts_summary=agent_drafts_summary,
            open_initiatives_summary=open_initiatives_summary,
        )
    else:
        conv_history = state.get("conversation_history", [])  # type: ignore[typeddict-item]
        history_text = "\n".join(
            f"{m['role']}: {m['content_he']}"
            for m in (conv_history[-6:] if len(conv_history) > 6 else conv_history)
        )
        ctx_text = "\n".join(
            f"[{r['agent_name']}:{r['run_id'][:8]}] {r['snippet']}"
            for r in state["retrieved_context"]
        )
        user_content = CHAT_TEMPLATE.format(
            conversation_history=history_text or "ראשית שיחה.",
            retrieved_context=ctx_text or "לא נמצא הקשר רלוונטי.",
            user_query=state["user_query"],
        )

    messages = [{"role": "user", "content": user_content}]
    tools_called: list[dict] = []
    response_text = ""

    # Agentic tool-use loop (max 5 rounds to prevent runaway)
    for _ in range(5):
        resp = client.messages.create(
            model=_MODEL,
            max_tokens=2000,
            system=[{"type": "text", "text": CHIEF_SYSTEM, "cache_control": {"type": "ephemeral"}}],
            tools=TOOL_DEFINITIONS,
            messages=messages,
        )

        # Collect any tool calls
        tool_use_blocks = [b for b in resp.content if b.type == "tool_use"]
        text_blocks = [b for b in resp.content if b.type == "text"]
        if text_blocks:
            response_text = text_blocks[-1].text

        if not tool_use_blocks:
            break

        # Execute tools and feed results back
        tool_results = []
        for tb in tool_use_blocks:
            result = execute_tool(tb.name, tb.input)
            tools_called.append({"tool": tb.name, "input": tb.input, "result": result})
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tb.id,
                "content": json.dumps(result, ensure_ascii=False, default=str),
            })

        messages.append({"role": "assistant", "content": resp.content})
        messages.append({"role": "user", "content": tool_results})

    state["draft_brief"] = response_text
    state["tool_calls_made"] = tools_called
    return state


# ---------------------------------------------------------------------------
# Node: validate_grounding
# ---------------------------------------------------------------------------

_CITATION_RE = re.compile(r"\[([a-z_]+):([0-9a-f\-]{8,})\]", re.IGNORECASE)


def validate_grounding(state: ChiefState) -> ChiefState:
    text_to_check = state["draft_brief"]
    matches = _CITATION_RE.findall(text_to_check)

    if matches:
        citations = [{"source_agent": m[0], "draft_id": m[1]} for m in matches]
        state["citations"] = citations
        state["grounding_ok"] = True
        state["final_response"] = text_to_check
        return state

    # No citations found — if there's factual content, regenerate with stronger instruction
    if len(text_to_check.strip()) < 50:
        # Short/empty response — accept as-is
        state["citations"] = []
        state["grounding_ok"] = True
        state["final_response"] = text_to_check
        return state

    # Attempt forced regeneration
    client = Anthropic()
    regen = client.messages.create(
        model=_MODEL,
        max_tokens=1500,
        system=[{"type": "text", "text": CHIEF_SYSTEM, "cache_control": {"type": "ephemeral"}}],
        messages=[
            {"role": "user", "content": (
                "התגובה שלך לא הכילה ציטוטים בפורמט [source_agent:draft_id]. "
                "חובה להוסיף ציטוט לכל עובדה. "
                "אנא כתוב מחדש:\n\n" + text_to_check
            )},
        ],
    )
    regenerated = regen.content[0].text if regen.content else text_to_check
    new_matches = _CITATION_RE.findall(regenerated)
    state["citations"] = [{"source_agent": m[0], "draft_id": m[1]} for m in new_matches]
    state["grounding_ok"] = bool(new_matches)
    state["final_response"] = regenerated
    return state


# ---------------------------------------------------------------------------
# Node: persist_output
# ---------------------------------------------------------------------------

def persist_output(state: ChiefState) -> ChiefState:
    # Persistence is handled by briefs.py / chat.py wrappers — graph just returns state
    return state


# ---------------------------------------------------------------------------
# Graph construction
# ---------------------------------------------------------------------------

def _route_after_gather(state: ChiefState) -> str:
    if state["mode"] == "chat":
        return "retrieve_relevant_context"
    return "synthesize_or_answer"


def build_chief_graph() -> object:
    g = StateGraph(ChiefState)
    g.add_node("gather_recent_activity", gather_recent_activity)
    g.add_node("retrieve_relevant_context", retrieve_relevant_context)
    g.add_node("synthesize_or_answer", synthesize_or_answer)
    g.add_node("validate_grounding", validate_grounding)
    g.add_node("persist_output", persist_output)

    g.set_entry_point("gather_recent_activity")
    g.add_conditional_edges(
        "gather_recent_activity",
        _route_after_gather,
        {
            "retrieve_relevant_context": "retrieve_relevant_context",
            "synthesize_or_answer": "synthesize_or_answer",
        },
    )
    g.add_edge("retrieve_relevant_context", "synthesize_or_answer")
    g.add_edge("synthesize_or_answer", "validate_grounding")
    g.add_edge("validate_grounding", "persist_output")
    g.add_edge("persist_output", END)
    return g.compile()
