from datetime import UTC, datetime, timedelta

from agent_server.services import session_run
from agent_server.services.session_run import _active_run_is_stale


def _run(started_at: str) -> dict[str, object]:
    return {"started_at": started_at}


def test_recent_run_is_not_stale(monkeypatch) -> None:
    monkeypatch.setattr(session_run, "_STALE_RUN_TTL_SECONDS", 900)
    recent = (datetime.now(UTC) - timedelta(seconds=30)).isoformat()

    assert _active_run_is_stale(_run(recent)) is False


def test_old_run_is_stale(monkeypatch) -> None:
    monkeypatch.setattr(session_run, "_STALE_RUN_TTL_SECONDS", 900)
    old = (datetime.now(UTC) - timedelta(seconds=1000)).isoformat()

    assert _active_run_is_stale(_run(old)) is True


def test_missing_or_bad_timestamp_is_not_stale() -> None:
    assert _active_run_is_stale({}) is False
    assert _active_run_is_stale({"started_at": "not-a-date"}) is False
