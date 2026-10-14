"""Group names the Claude desktop app keeps for its own sessions.

The app stores its group definitions and per-session assignments in its local
config, keyed by the app's own session ids. Each assignment names a metadata
file that also carries the CLI session id the Connector knows, so reading both
gives a group name per session.

The layout is macOS-specific and entirely optional: a missing directory or an
unreadable file just means no sessions have groups.
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

CONFIG_DIRECTORY = "~/Library/Application Support/Claude-3p"
CONFIG_FILE_NAME = "claude_desktop_config.json"
SESSION_FILES_GLOB = "claude-code-sessions/*/*/local_*.json"

# The files only change when the user regroups, and every session read asks for
# the same map.
GROUP_CACHE_TTL_SECONDS = 300.0

# Assignment keys look like `code:local_<app session id>`.
ASSIGNMENT_PREFIX = "code:"

_session_groups: tuple[float, dict[str, str]] | None = None


def session_group_names(
    config_directory: str | Path | None = None,
    *,
    clock: Callable[[], float] = time.monotonic,
) -> dict[str, str]:
    """Map each CLI session id to the desktop app group that holds it."""

    global _session_groups

    now = clock()
    if _session_groups is not None and now < _session_groups[0]:
        return _session_groups[1]
    names = _read_group_names(
        Path(config_directory or CONFIG_DIRECTORY).expanduser(),
    )
    _session_groups = (now + GROUP_CACHE_TTL_SECONDS, names)
    return names


def group_name_for(session_id: str | None) -> str | None:
    if not session_id:
        return None
    return session_group_names().get(session_id)


def _read_group_names(directory: Path) -> dict[str, str]:
    try:
        groups, assignments = _read_definitions(directory / CONFIG_FILE_NAME)
    except (OSError, ValueError):
        return {}
    if not assignments:
        return {}
    cli_ids = _read_cli_session_ids(directory, assignments)
    return {
        cli_ids[app_session_id]: groups[group_id]
        for app_session_id, group_id in assignments.items()
        if app_session_id in cli_ids and groups.get(group_id)
    }


def _read_definitions(path: Path) -> tuple[dict[str, str], dict[str, str]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    scope = _find_scope(payload)
    if scope is None:
        return {}, {}
    raw_groups = scope.get("groups")
    groups = {
        str(item["id"]): str(item.get("name") or "")
        for item in (raw_groups if isinstance(raw_groups, list) else ())
        if isinstance(item, Mapping) and item.get("id")
    }
    raw_assignments = scope.get("assignments")
    assignments = {
        str(key)[len(ASSIGNMENT_PREFIX) :]: str(value)
        for key, value in (
            raw_assignments.items() if isinstance(raw_assignments, Mapping) else ()
        )
        if str(key).startswith(ASSIGNMENT_PREFIX)
    }
    return groups, assignments


def _find_scope(payload: Any) -> Mapping[str, Any] | None:
    """The group scope sits under a per-account, per-org path we do not pin."""

    if isinstance(payload, Mapping):
        if "groups" in payload or "assignments" in payload:
            return payload
        for value in payload.values():
            found = _find_scope(value)
            if found is not None:
                return found
    elif isinstance(payload, list):
        for value in payload:
            found = _find_scope(value)
            if found is not None:
                return found
    return None


def _read_cli_session_ids(
    directory: Path,
    assignments: Mapping[str, str],
) -> dict[str, str]:
    wanted = set(assignments)
    cli_ids: dict[str, str] = {}
    for path in directory.glob(SESSION_FILES_GLOB):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(payload, Mapping):
            continue
        app_session_id = payload.get("sessionId")
        cli_session_id = payload.get("cliSessionId")
        if (
            isinstance(app_session_id, str)
            and app_session_id in wanted
            and isinstance(cli_session_id, str)
            and cli_session_id
        ):
            cli_ids[app_session_id] = cli_session_id
    return cli_ids
