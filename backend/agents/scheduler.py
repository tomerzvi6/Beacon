from apscheduler.schedulers.blocking import BlockingScheduler


def main() -> None:
    scheduler = BlockingScheduler(timezone="Asia/Jerusalem")
    # Nudger: daily 09:00; Analyst: weekly Sun 08:00 — wired in Phase 4.
    scheduler.start()


if __name__ == "__main__":
    main()
