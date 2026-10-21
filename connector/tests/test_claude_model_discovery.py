from __future__ import annotations

import asyncio
from typing import Any

import pytest

from connector.runtimes.claude.catalogs import discovery as discovery_module
from connector.runtimes.claude.catalogs.discovery import (
    CLAUDE_MODEL_DISCOVERY_TTL_SECONDS,
    ClaudeModelDiscovery,
)


class _Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def _model_list(*values: str) -> tuple[dict[str, Any], ...]:
    return tuple({"value": value} for value in values)


@pytest.fixture
def settings_fingerprint(monkeypatch: pytest.MonkeyPatch) -> dict[str, str]:
    state = {"value": "fp-1"}
    monkeypatch.setattr(
        discovery_module,
        "claude_settings_fingerprint",
        lambda: state["value"],
    )
    return state


def test_models_reads_once_within_the_ttl(
    monkeypatch: pytest.MonkeyPatch,
    settings_fingerprint: dict[str, str],
) -> None:
    clock = _Clock()
    reads = 0

    async def fake_read_models(
        self: ClaudeModelDiscovery,
    ) -> tuple[dict[str, Any], ...]:
        nonlocal reads
        reads += 1
        return _model_list("only")

    monkeypatch.setattr(ClaudeModelDiscovery, "_read_models", fake_read_models)

    async def run() -> None:
        subject = ClaudeModelDiscovery(config_values={}, clock=clock)
        assert await subject.models() == _model_list("only")
        clock.now += CLAUDE_MODEL_DISCOVERY_TTL_SECONDS - 1
        assert await subject.models() == _model_list("only")
        assert reads == 1

    asyncio.run(run())


def test_ttl_expiry_serves_stale_without_waiting_for_the_refresh(
    monkeypatch: pytest.MonkeyPatch,
    settings_fingerprint: dict[str, str],
) -> None:
    """The refresh is a ~4-5s SDK handshake; callers must not pay for it."""
    clock = _Clock()
    release = asyncio.Event()
    refresh_started = asyncio.Event()
    reads = 0

    async def fake_read_models(
        self: ClaudeModelDiscovery,
    ) -> tuple[dict[str, Any], ...]:
        nonlocal reads
        reads += 1
        if reads == 1:
            return _model_list("first")
        refresh_started.set()
        await release.wait()
        return _model_list("second")

    monkeypatch.setattr(ClaudeModelDiscovery, "_read_models", fake_read_models)

    async def run() -> None:
        subject = ClaudeModelDiscovery(config_values={}, clock=clock)
        assert await subject.models() == _model_list("first")
        clock.now += CLAUDE_MODEL_DISCOVERY_TTL_SECONDS + 1

        # Parked on `release`: a stale-while-revalidate read still returns.
        stale = await asyncio.wait_for(subject.models(stale_ok=True), timeout=1.0)
        assert stale == _model_list("first")
        await asyncio.wait_for(refresh_started.wait(), timeout=1.0)

        release.set()
        for _ in range(10):
            await asyncio.sleep(0)
            if subject._inflight is None:
                break
        assert await subject.models() == _model_list("second")

    asyncio.run(run())


def test_settings_change_reads_fresh_instead_of_serving_stale(
    monkeypatch: pytest.MonkeyPatch,
    settings_fingerprint: dict[str, str],
) -> None:
    """A remapped alias changes the list itself, so that read must block."""
    clock = _Clock()
    served = {"value": "first"}

    async def fake_read_models(
        self: ClaudeModelDiscovery,
    ) -> tuple[dict[str, Any], ...]:
        return _model_list(served["value"])

    monkeypatch.setattr(ClaudeModelDiscovery, "_read_models", fake_read_models)

    async def run() -> None:
        subject = ClaudeModelDiscovery(config_values={}, clock=clock)
        assert await subject.models(stale_ok=True) == _model_list("first")

        settings_fingerprint["value"] = "fp-2"
        served["value"] = "second"
        # stale_ok must not hide a settings change: the list itself may differ.
        assert await subject.models(stale_ok=True) == _model_list("second")

    asyncio.run(run())
