"""
APScheduler entry point — wires all agents to their cron triggers.
Run with: python agents/scheduler.py
"""
import logging

from apscheduler.schedulers.blocking import BlockingScheduler

from agents.graphs.analyst import run_analyst
from agents.graphs.nudger import run_nudger
from agents.graphs.support import run_support

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("beacon.scheduler")


def job_nudger() -> None:
    log.info("[Nudger] Starting run...")
    try:
        result = run_nudger()
        run_id = result.get("run_id", "")
        log.info(f"[Nudger] Done. run_id={run_id or 'no draft (no unclaimed tasks)'}")
    except Exception:
        log.exception("[Nudger] Failed")


def job_support() -> None:
    log.info("[Support] Starting run...")
    try:
        result = run_support()
        run_id = result.get("run_id", "")
        log.info(f"[Support] Done. run_id={run_id or 'no draft (no new tickets)'}")
    except Exception:
        log.exception("[Support] Failed")


def job_analyst() -> None:
    log.info("[Analyst] Starting run...")
    try:
        result = run_analyst()
        log.info(f"[Analyst] Done. run_id={result.get('run_id', '')}")
    except Exception:
        log.exception("[Analyst] Failed")


def main() -> None:
    scheduler = BlockingScheduler(timezone="Asia/Jerusalem")

    # Nudger: daily 09:00
    scheduler.add_job(job_nudger, "cron", hour=9, minute=0, id="nudger")

    # Support: every 30 minutes during business hours
    scheduler.add_job(job_support, "cron", hour="8-20", minute="*/30", id="support")

    # Analyst: every Sunday at 08:00
    scheduler.add_job(job_analyst, "cron", day_of_week="sun", hour=8, minute=0, id="analyst")

    log.info("Scheduler started. Jobs: nudger (daily 09:00), support (every 30m), analyst (Sun 08:00)")
    scheduler.start()


if __name__ == "__main__":
    main()
