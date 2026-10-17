from __future__ import annotations

import json
from pathlib import Path

import claude_agent_sdk

from connector.runtimes.claude.domain.session import ClaudeSession
from connector.runtimes.claude.sdk import client as claude_client
from connector.runtimes.claude.sdk import settings as claude_settings
from connector.runtimes.claude.sdk.client import (
    build_sdk_options,
    claude_sdk_environment,
)
from connector.runtimes.claude.sdk.settings import claude_user_settings_environment


def test_claude_sdk_buffer_handles_25_mib_image_read_result() -> None:
    options = build_sdk_options(
        claude_agent_sdk,
        {},
        ClaudeSession(session_id="sess_buffer"),
    )

    attachment_bytes = 25 * 1024 * 1024
    base64_bytes = 4 * ((attachment_bytes + 2) // 3)
    duplicated_read_result_bytes = 2 * base64_bytes
    json_overhead_bytes = 1024 * 1024

    assert options.max_buffer_size >= (
        duplicated_read_result_bytes + json_overhead_bytes
    )


def test_claude_user_settings_environment_reads_only_model_names(
    tmp_path: Path,
) -> None:
    path = tmp_path / "settings.json"
    path.write_text(
        json.dumps(
            {
                "env": {
                    "ANTHROPIC_DEFAULT_OPUS_MODEL": "example-model-a",
                    "ANTHROPIC_MODEL": "example-model-b",
                    "ANTHROPIC_AUTH_TOKEN": "opaque-value",
                    "ANTHROPIC_BASE_URL": "https://example.invalid/go",
                    "API_TIMEOUT_MS": "3000000",
                }
            }
        ),
        encoding="utf-8",
    )

    assert claude_user_settings_environment(str(path)) == {
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "example-model-a",
        "ANTHROPIC_MODEL": "example-model-b",
    }


def test_claude_user_settings_environment_tolerates_absent_or_invalid_file(
    tmp_path: Path,
) -> None:
    assert claude_user_settings_environment(str(tmp_path / "missing.json")) == {}

    broken = tmp_path / "broken.json"
    broken.write_text("{ not json", encoding="utf-8")
    assert claude_user_settings_environment(str(broken)) == {}

    empty_env = tmp_path / "empty-env.json"
    empty_env.write_text(json.dumps({"env": {"ANTHROPIC_MODEL": ""}}), encoding="utf-8")
    assert claude_user_settings_environment(str(empty_env)) == {}


def test_claude_sdk_environment_lets_runtime_config_override_user_settings(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        claude_settings,
        "claude_user_settings_environment",
        lambda path=None: {
            "ANTHROPIC_MODEL": "example-model-a",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "example-model-b",
        },
    )

    environment = claude_sdk_environment(
        {"environment": {"ANTHROPIC_MODEL": "runtime-model"}}
    )

    assert environment == {
        "ANTHROPIC_MODEL": "runtime-model",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "example-model-b",
    }


def test_cli_permission_mode_avoids_bypass_when_running_as_root(monkeypatch) -> None:
    monkeypatch.setattr(claude_client, "_runs_as_root", lambda: True)

    assert claude_client.cli_permission_mode("bypassPermissions") == "default"
    assert claude_client.cli_permission_mode("plan") == "plan"


def test_cli_permission_mode_keeps_bypass_off_root(monkeypatch) -> None:
    monkeypatch.setattr(claude_client, "_runs_as_root", lambda: False)

    assert claude_client.cli_permission_mode("bypassPermissions") == "bypassPermissions"
