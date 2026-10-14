from __future__ import annotations

import asyncio
from typing import Any

import pytest
from test_runtime_instance_routing import _insert_connector

from agent_server.core.catalogs import (
    CatalogDomainError,
    CatalogType,
    CatalogUpdateOutcome,
    validate_model_catalog,
    validate_permission_catalog,
)
from agent_server.core.protocol import (
    ProtocolModelCatalog,
    ProtocolModelItem,
    ProtocolPermissionCatalog,
    ProtocolPermissionItem,
    ProtocolReasoningItem,
)
from agent_server.infra.repositories.facade import Store
from agent_server.services.catalogs import CatalogService, CatalogServiceError


def test_model_catalog_accepts_one_default_and_unique_selections() -> None:
    catalog = _model_catalog()

    validate_model_catalog(catalog)


def test_model_catalog_rejects_duplicate_selection_ids() -> None:
    catalog = _model_catalog().model_copy(
        update={
            "models": [
                *_model_catalog().models,
                ProtocolModelItem(
                    id="gpt-other",
                    displayName="Other",
                    selectionId="sel_model_high",
                ),
            ]
        }
    )

    with pytest.raises(CatalogDomainError, match="duplicate model selection id"):
        validate_model_catalog(catalog)


def test_model_catalog_rejects_multiple_defaults() -> None:
    first = ProtocolModelItem(
        id="first",
        displayName="First",
        selectionId="sel_first",
        default=True,
    )
    second = ProtocolModelItem(
        id="second",
        displayName="Second",
        selectionId="sel_second",
        default=True,
    )
    catalog = ProtocolModelCatalog(runtime="codex", revision=1, models=[first, second])

    with pytest.raises(CatalogDomainError, match="multiple defaults"):
        validate_model_catalog(catalog)


def test_model_catalog_rejects_unselectable_model() -> None:
    catalog = ProtocolModelCatalog(
        runtime="codex",
        revision=1,
        models=[ProtocolModelItem(id="empty", displayName="Empty")],
    )

    with pytest.raises(CatalogDomainError, match="must define a selection id"):
        validate_model_catalog(catalog)


def test_permission_catalog_rejects_duplicate_ids() -> None:
    catalog = ProtocolPermissionCatalog(
        runtime="codex",
        revision=1,
        permissions=[
            ProtocolPermissionItem(
                id="default",
                displayName="Default",
                selectionId="sel_default",
            ),
            ProtocolPermissionItem(
                id="default",
                displayName="Duplicate",
                selectionId="sel_duplicate",
            ),
        ],
    )

    with pytest.raises(CatalogDomainError, match="duplicate permission id"):
        validate_permission_catalog(catalog)


def test_catalog_service_resolves_stable_selection_ids() -> None:
    repository = _CatalogRepository(
        model=_model_catalog().model_dump(mode="json"),
        permission=_permission_catalog().model_dump(mode="json"),
    )
    service = CatalogService(repository)

    model = asyncio.run(
        service.resolve_model(
            "connector-1",
            runtime_id="rti_work",
            selection_id="sel_model_high",
        )
    )
    permission = asyncio.run(
        service.resolve_permission(
            "connector-1",
            runtime_id="rti_work",
            selection_id="sel_permission_default",
        )
    )

    assert model == ("gpt-example", "high")
    assert permission == {"permissionMode": "default"}


def test_catalog_service_rejects_equal_revision_content_conflict() -> None:
    repository = _CatalogRepository(outcome="conflict")
    service = CatalogService(repository)

    with pytest.raises(CatalogServiceError) as raised:
        asyncio.run(
            service.ingest(
                "connector-1",
                catalog_type="model",
                payload=_model_catalog().model_dump(mode="json"),
            )
        )

    assert raised.value.code == "catalog_revision_conflict"


class _CatalogRepository:
    def __init__(
        self,
        *,
        model: dict[str, Any] | None = None,
        permission: dict[str, Any] | None = None,
        outcome: CatalogUpdateOutcome = "accepted",
    ) -> None:
        self.catalogs = {"model": model, "permission": permission}
        self.outcome = outcome

    async def get_protocol_catalog(
        self,
        connector_id: str,
        *,
        runtime_id: str,
        catalog_type: CatalogType,
        user_id: str | None = None,
    ) -> dict[str, Any] | None:
        assert connector_id == "connector-1"
        assert runtime_id == "rti_work"
        return self.catalogs[catalog_type]

    async def update_protocol_catalog(
        self,
        connector_id: str,
        *,
        runtime: str,
        runtime_id: str | None = None,
        catalog_type: CatalogType,
        revision: int,
        catalog: dict[str, Any],
    ) -> CatalogUpdateOutcome:
        assert connector_id == "connector-1"
        assert runtime == "codex"
        assert runtime_id is None
        assert revision == catalog["revision"]
        return self.outcome


def _model_catalog() -> ProtocolModelCatalog:
    return ProtocolModelCatalog(
        runtime="codex",
        revision=3,
        models=[
            ProtocolModelItem(
                id="gpt-example",
                displayName="GPT Example",
                default=True,
                reasoningItems=[
                    ProtocolReasoningItem(
                        id="high",
                        displayName="High",
                        fullModelId="gpt-example",
                        selectionId="sel_model_high",
                        default=True,
                    )
                ],
            )
        ],
    )


def _permission_catalog() -> ProtocolPermissionCatalog:
    return ProtocolPermissionCatalog(
        runtime="codex",
        revision=4,
        permissions=[
            ProtocolPermissionItem(
                id="default",
                displayName="Default",
                selectionId="sel_permission_default",
                default=True,
            )
        ],
    )


def _claude_alias_catalog(revision: int, title: str) -> dict[str, Any]:
    return {
        "runtime": "claude",
        "revision": revision,
        "models": [
            {
                "id": "opus",
                "title": title,
                "selectionId": "sel_claude_opus",
                "description": "Opus alias",
                "reasoningItems": [],
                "metadata": {"source": "claude-code.initialize"},
            }
        ],
    }


def test_catalog_update_takes_changed_content_at_a_higher_revision() -> None:
    """The Connector relies on this to republish a renamed model list.

    A provider switch rewrites the model names behind the aliases, which
    changes the catalog content without any runtime config change, so the
    revision has to be the only thing standing between the two publishes.
    """

    store = Store()

    async def run() -> None:
        await _insert_connector(store, "conn_alias")
        published = _claude_alias_catalog(5005, "Claude Opus 5")
        switched = _claude_alias_catalog(5005, "deepseek-v4.1-flash")

        async def ingest(
            revision: int,
            catalog: dict[str, Any],
        ) -> CatalogUpdateOutcome:
            return await store.update_protocol_catalog(
                "conn_alias",
                runtime="claude",
                runtime_id="claude",
                catalog_type="model",
                revision=revision,
                catalog=catalog,
            )

        assert await ingest(5005, published) == "accepted"
        # Equal revision with different content: the platform keeps what it has.
        assert await ingest(5005, switched) == "conflict"
        # The Connector's input fingerprint moves the revision past the publish.
        assert await ingest(5006, switched) == "accepted"
        assert (
            await store.get_protocol_catalog(
                "conn_alias",
                runtime_id="claude",
                catalog_type="model",
            )
            == switched
        )

    try:
        asyncio.run(run())
    finally:
        asyncio.run(store.close())
