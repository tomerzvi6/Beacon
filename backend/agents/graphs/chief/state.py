"""ChiefState — shared state type for Chief Agent's LangGraph."""
from typing import Literal, TypedDict


class ChiefState(TypedDict, total=False):
    mode: Literal["brief", "chat"]
    conversation_id: str
    user_query: str                 # empty string in brief mode
    recent_drafts: list[dict]       # [{run_id, agent_name, draft_type, content_preview, created_at}]
    open_initiatives: list[dict]    # [{id, target_agent, title_he, status, last_check_at}]
    retrieved_context: list[dict]   # [{run_id, agent_name, snippet, score}]
    conversation_history: list[dict]  # [{role, content_he}] — chat mode only
    draft_brief: str                # raw LLM output before validation
    tool_calls_made: list[dict]     # log of tools invoked this turn
    final_response: str             # validated, citation-checked response
    citations: list[dict]           # [{source_agent, draft_id, claim}]
    grounding_ok: bool              # True after validate_grounding passes
