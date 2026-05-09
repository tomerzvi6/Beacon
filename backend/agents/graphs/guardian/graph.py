"""
Guardian agent — daily security & privacy auditor.
Read-only on DB + audit_log. Produces a severity-ranked security brief.

Graph: gather → check → analyze → propose
"""
from typing import TypedDict

import os

from anthropic import Anthropic
from langgraph.graph import END, StateGraph
from sqlalchemy.orm import Session

_MODEL = os.environ.get("GUARDIAN_MODEL", "claude-sonnet-4-6")

from agents.db import get_engine
from agents.graphs._pending_tasks import process_pending_tasks_for_agent
from agents.graphs.guardian.checks import (
    detect_cross_household_anomalies,
    detect_offhours_access,
    detect_phi_in_agent_views,
    detect_unusual_volume,
    get_recent_audit_entries,
    probe_phi_table_access,
    probe_view_exposes_only_aggregates,
)
from shared.models import AgentRun


class GuardianState(TypedDict):
    audit_entries: list[dict]
    findings: list[dict]
    rls_results: dict[str, bool]
    brief_markdown: str
    run_id: str


def process_pending_tasks(state: GuardianState) -> GuardianState:
    """Pick up and execute tasks queued for this agent by the Chief Agent."""
    process_pending_tasks_for_agent("guardian")
    return state


def gather(state: GuardianState) -> GuardianState:
    """Pull last 24h of audit_log entries."""
    engine = get_engine()
    state["audit_entries"] = get_recent_audit_entries(engine, hours=24)
    return state


def check(state: GuardianState) -> GuardianState:
    """Run all security checks and aggregate findings."""
    engine = get_engine()
    entries = state["audit_entries"]

    findings: list[dict] = []
    findings.extend(detect_offhours_access(entries))
    findings.extend(detect_unusual_volume(entries))
    findings.extend(detect_cross_household_anomalies(entries))
    findings.extend(detect_phi_in_agent_views(engine))
    findings.extend(probe_view_exposes_only_aggregates(engine))

    rls_results = probe_phi_table_access(engine)

    # Convert failed RLS probes into findings
    for check_name, passed in rls_results.items():
        if not passed:
            findings.append({
                "finding": "rls_probe_failed",
                "severity": "critical",
                "check": check_name,
                "detail": "PHI table or column readable by agent_role — expected PermissionError",
            })

    state["findings"] = findings
    state["rls_results"] = rls_results
    return state


def analyze(state: GuardianState) -> GuardianState:
    """Ask Claude to produce a severity-ranked security brief in Hebrew Markdown."""
    entries_count = len(state["audit_entries"])
    findings = state["findings"]
    rls_all_pass = all(state["rls_results"].values())

    if not findings and rls_all_pass:
        state["brief_markdown"] = (
            "## 🛡️ דוח אבטחה יומי\n\n**✅ הכל תקין** — לא נמצאו ממצאים חריגים ב-24 השעות האחרונות.\n\n"
            f"- {entries_count} רשומות audit נסרקו\n"
            f"- כל {len(state['rls_results'])} בדיקות RLS עברו בהצלחה\n"
        )
        return state

    severity_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
    sorted_findings = sorted(findings, key=lambda f: severity_order.get(f.get("severity", "low"), 4))

    client = Anthropic()
    message = client.messages.create(
        model=_MODEL,
        max_tokens=1000,
        system=[{
            "type": "text",
            "text": (
                "אתה מנהל אבטחת מידע של מערכת רפואית. "
                "כתוב בריף אבטחה יומי בעברית בפורמט Markdown. "
                "דרג ממצאים לפי חומרה (CRITICAL > HIGH > MEDIUM). "
                "לכל ממצא: תיאור, השפעה אפשרית, והמלצה קונקרטית."
            ),
            "cache_control": {"type": "ephemeral"},
        }],
        messages=[{
            "role": "user",
            "content": (
                f"ממצאי סריקת האבטחה ({entries_count} רשומות audit, 24 שעות אחרונות):\n\n"
                f"בדיקות RLS: {'✅ עברו' if rls_all_pass else '❌ כשלו'}\n\n"
                f"ממצאים ({len(findings)}):\n"
                + "\n".join(f"- [{f.get('severity','?').upper()}] {f}" for f in sorted_findings)
            ),
        }],
    )

    state["brief_markdown"] = message.content[0].text if message.content else ""
    return state


def propose(state: GuardianState) -> GuardianState:
    """Insert agent_runs row with security brief awaiting Tomer's review."""
    critical_count = sum(1 for f in state["findings"] if f.get("severity") == "critical")
    high_count = sum(1 for f in state["findings"] if f.get("severity") == "high")

    run = AgentRun(
        agent_name="guardian",
        status="awaiting_approval",
        input_summary={
            "audit_entries_scanned": len(state["audit_entries"]),
            "findings_count": len(state["findings"]),
            "critical": critical_count,
            "high": high_count,
            "rls_all_pass": all(state["rls_results"].values()),
        },
        output_draft={
            "type": "security_brief",
            "markdown": state["brief_markdown"],
            "findings": state["findings"],
            "rls_results": state["rls_results"],
        },
    )

    with Session(get_engine()) as session:
        session.add(run)
        session.commit()
        state["run_id"] = str(run.id)

    return state


def build_guardian_graph() -> StateGraph:
    g = StateGraph(GuardianState)
    g.add_node("process_pending_tasks", process_pending_tasks)
    g.add_node("gather", gather)
    g.add_node("check", check)
    g.add_node("analyze", analyze)
    g.add_node("propose", propose)
    g.set_entry_point("process_pending_tasks")
    g.add_edge("process_pending_tasks", "gather")
    g.add_edge("gather", "check")
    g.add_edge("check", "analyze")
    g.add_edge("analyze", "propose")
    g.add_edge("propose", END)
    return g.compile()


def run_guardian() -> dict:
    return build_guardian_graph().invoke({
        "audit_entries": [],
        "findings": [],
        "rls_results": {},
        "brief_markdown": "",
        "run_id": "",
    })
