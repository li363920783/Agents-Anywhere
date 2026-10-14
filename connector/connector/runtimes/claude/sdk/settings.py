from __future__ import annotations

import hashlib
import json
import os
import tempfile
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from connector.logging import logger
from connector.runtimes.model_gateway import model_gateway_from_config

CLAUDE_USER_SETTINGS_PATH = "~/.claude/settings.json"

# Model names a provider switcher (cc-switch and friends) rewrites in the user's
# Claude Code settings. Credentials and endpoints stay out: those belong to the
# runtime config, where modelGateway may override them.
CLAUDE_MODEL_ENV_KEYS = (
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_FABLE_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
)


def claude_user_settings_environment(path: str | None = None) -> dict[str, str]:
    """Read the model-name environment the user's Claude Code settings define.

    Claude Code builds the model list it reports from the process environment,
    so an alias remapped only in the settings file
    (`ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4.1-flash`) never shows up there:
    the CLI keeps reporting the bundled models. Forwarding these keys makes the
    runtime follow the same mapping the user's own `claude` shell does.
    """

    settings_path = Path(path or os.path.expanduser(CLAUDE_USER_SETTINGS_PATH))
    try:
        payload = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if not isinstance(payload, Mapping):
        return {}
    env = payload.get("env")
    if not isinstance(env, Mapping):
        return {}
    return {
        key: env[key]
        for key in CLAUDE_MODEL_ENV_KEYS
        if isinstance(env.get(key), str) and env[key]
    }


def claude_settings_fingerprint(path: str | None = None) -> str:
    """Stable digest of the settings-defined model mapping.

    Caches key off this so switching provider takes effect on the next read
    instead of waiting out the discovery TTL. Empty mapping digests to "".
    """

    environment = claude_user_settings_environment(path)
    if not environment:
        return ""
    payload = json.dumps(sorted(environment.items()), ensure_ascii=True)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def create_gateway_settings_file(config_values: Mapping[str, Any]) -> str | None:
    model_gateway = model_gateway_from_config(config_values.get("modelGateway"))
    if model_gateway is None:
        return None

    file_descriptor, raw_path = tempfile.mkstemp(
        prefix="agents-anywhere-claude-",
        suffix=".json",
    )
    path = Path(raw_path)
    try:
        os.chmod(path, 0o600)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as settings_file:
            json.dump(
                {
                    "env": {
                        "ANTHROPIC_BASE_URL": model_gateway.base_url,
                        "ANTHROPIC_AUTH_TOKEN": model_gateway.api_key,
                        "ANTHROPIC_API_KEY": "",
                    }
                },
                settings_file,
                ensure_ascii=True,
                separators=(",", ":"),
            )
            settings_file.write("\n")
    except BaseException:
        try:
            os.close(file_descriptor)
        except OSError:
            pass
        path.unlink(missing_ok=True)
        raise
    return str(path)


def remove_gateway_settings_file(path: str | None) -> None:
    if path is None:
        return
    try:
        Path(path).unlink(missing_ok=True)
    except OSError:
        logger.exception("Claude Gateway settings cleanup failed path={}", path)
