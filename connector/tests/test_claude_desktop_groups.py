from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

from connector.runtimes.claude.sessions import desktop_groups
from connector.runtimes.claude.sessions.reader import _session_title


def _write_desktop_app(
    directory: Path,
    *,
    groups: list[dict[str, str]],
    assignments: dict[str, str],
    sessions: dict[str, dict[str, str]],
) -> None:
    session_dir = directory / "claude-code-sessions" / "account" / "org"
    session_dir.mkdir(parents=True, exist_ok=True)
    (directory / "claude_desktop_config.json").write_text(
        json.dumps(
            {
                "preferences": {
                    "epitaxyPrefs": {
                        "dframe-group-scopes": {
                            "account": [
                                {"org": {"groups": groups, "assignments": assignments}}
                            ]
                        }
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    for app_session_id, payload in sessions.items():
        (session_dir / f"{app_session_id}.json").write_text(
            json.dumps(payload),
            encoding="utf-8",
        )


def test_session_group_names_joins_config_and_session_metadata(
    tmp_path: Path,
    monkeypatch,
) -> None:
    monkeypatch.setattr(desktop_groups, "_session_groups", None)
    _write_desktop_app(
        tmp_path,
        groups=[
            {"id": "cg-1", "name": "followup-online"},
            {"id": "cg-2", "name": "meeting-2026"},
        ],
        assignments={
            "code:local_app-1": "cg-1",
            "code:local_app-2": "cg-2",
            # Assigned, but its own metadata file does not exist yet.
            "code:local_app-3": "cg-1",
        },
        sessions={
            "local_app-1": {"sessionId": "local_app-1", "cliSessionId": "cli-1"},
            "local_app-2": {"sessionId": "local_app-2", "cliSessionId": "cli-2"},
        },
    )

    assert desktop_groups.session_group_names(tmp_path) == {
        "cli-1": "followup-online",
        "cli-2": "meeting-2026",
    }


def test_session_group_names_is_empty_without_the_desktop_app(
    tmp_path: Path,
    monkeypatch,
) -> None:
    monkeypatch.setattr(desktop_groups, "_session_groups", None)

    assert desktop_groups.session_group_names(tmp_path) == {}


def test_session_group_names_ignores_an_unreadable_config(
    tmp_path: Path,
    monkeypatch,
) -> None:
    monkeypatch.setattr(desktop_groups, "_session_groups", None)
    (tmp_path / "claude_desktop_config.json").write_text(
        "{ not json",
        encoding="utf-8",
    )

    assert desktop_groups.session_group_names(tmp_path) == {}


def test_session_title_prefixes_the_desktop_app_group(monkeypatch) -> None:
    monkeypatch.setattr(
        desktop_groups,
        "group_name_for",
        lambda session_id: "followup-online" if session_id == "cli-1" else None,
    )
    session = SimpleNamespace(custom_title="随访二期1010需求")

    assert _session_title(session, "cli-1") == "[followup-online] 随访二期1010需求"
    assert _session_title(session, "cli-untracked") == "随访二期1010需求"
    assert _session_title(SimpleNamespace(), "cli-1") is None
