from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field, replace
from typing import Any

from connector.runtime_protocol import (
    RuntimeConfig,
    RuntimeInvalidRequestError,
    RuntimeModelCatalog,
    RuntimePermissionCatalog,
)
from connector.runtime_protocol.host import RuntimeHostClient
from connector.runtimes.catalog_revisions import (
    CATALOG_CONFIG_REVISION_FACTOR,
    runtime_catalog_revision,
)
from connector.runtimes.claude.catalogs.discovery import ClaudeModelDiscovery
from connector.runtimes.claude.domain.models import (
    ClaudeModelSelection,
    claude_model_catalog,
    model_selection_from_selection_id,
)
from connector.runtimes.claude.domain.permissions import claude_permission_catalog
from connector.runtimes.claude.sdk.client import SdkLoader

# The platform keeps the last catalog it accepted and rejects any later publish
# that keeps the revision while changing the content. The picker list depends on
# state this connector does not version - the CLI's own model list and the
# user's remapped aliases - so the revision carries a persisted counter that
# advances whenever those inputs change.
CLAUDE_MODEL_CATALOG_STATIC_REVISION = 5
CLAUDE_PERMISSION_CATALOG_STATIC_REVISION = 1
CATALOG_REVISION_STATE_KEY = "claude/catalog/model-revision"
# ponytail: counter shares the revision's low range, so it stops after 994
# input changes; give catalogs a wider revision space if that ever binds.
MAX_CATALOG_REVISION_OFFSET = (
    CATALOG_CONFIG_REVISION_FACTOR - CLAUDE_MODEL_CATALOG_STATIC_REVISION - 1
)


@dataclass(slots=True)
class ClaudeCatalogReader:
    config: RuntimeConfig
    sdk_loader: SdkLoader | None = None
    host: RuntimeHostClient | None = None
    discovery: ClaudeModelDiscovery = field(init=False)
    _revision_state: dict[str, Any] = field(default_factory=dict, init=False)

    def __post_init__(self) -> None:
        self.discovery = ClaudeModelDiscovery(
            config_values=self.config.values,
            sdk_loader=self.sdk_loader,
        )

    async def list_model_catalog(
        self,
        query: str | None = None,
        limit: int = 100,
    ) -> RuntimeModelCatalog:
        cli_models = await self.discovery.models() or ()
        custom_models = self.custom_models
        catalog = claude_model_catalog(
            revision=0,
            query=query,
            limit=limit,
            custom_models=custom_models,
            cli_models=cli_models,
        )
        revision = await self._revision(cli_models, custom_models)
        return replace(catalog, revision=revision)

    async def _revision(
        self,
        cli_models: Sequence[Mapping[str, Any]],
        custom_models: Any,
    ) -> int:
        fingerprint = catalog_inputs_fingerprint(cli_models, custom_models)
        state = await self._read_revision_state()
        offset = state.get("offset")
        if isinstance(offset, bool) or not isinstance(offset, int) or offset < 0:
            offset = 0
        if state.get("fingerprint") != fingerprint:
            offset = min(offset + 1, MAX_CATALOG_REVISION_OFFSET)
            await self._write_revision_state(
                {"fingerprint": fingerprint, "offset": offset}
            )
        return runtime_catalog_revision(
            self.config.revision,
            CLAUDE_MODEL_CATALOG_STATIC_REVISION + offset,
        )

    async def _read_revision_state(self) -> Mapping[str, Any]:
        if self.host is None:
            return self._revision_state
        state = await self.host.sync_state_read(CATALOG_REVISION_STATE_KEY)
        return state or {}

    async def _write_revision_state(self, state: Mapping[str, Any]) -> None:
        self._revision_state = dict(state)
        if self.host is not None:
            await self.host.sync_state_write(CATALOG_REVISION_STATE_KEY, state)

    async def resolve_model_selection(
        self,
        selection_id: str | None,
    ) -> ClaudeModelSelection | None:
        """Resolve a selection, reading the CLI list only when it is needed.

        A selection made from the CLI list (for example after a Connector
        restart) is unknown until discovery has run once.
        """

        try:
            return self.model_selection(selection_id)
        except RuntimeInvalidRequestError:
            # models() owns both the successful-cache and failed-read TTLs.
            # A previous attempt must not permanently reject a saved CLI id.
            pass
        await self.discovery.models()
        return self.model_selection(selection_id)

    def model_selection(self, selection_id: str | None) -> ClaudeModelSelection | None:
        return model_selection_from_selection_id(
            selection_id,
            self.custom_models,
            self.cli_models,
        )

    @property
    def cli_models(self) -> tuple[dict[str, Any], ...]:
        return self.discovery.cached_models

    async def list_permission_catalog(
        self,
        query: str | None = None,
        limit: int = 100,
    ) -> RuntimePermissionCatalog:
        return claude_permission_catalog(
            revision=runtime_catalog_revision(
                self.config.revision,
                CLAUDE_PERMISSION_CATALOG_STATIC_REVISION,
            ),
            query=query,
            limit=limit,
        )

    @property
    def custom_models(self) -> Any:
        return self.config.values.get("customModels")


def catalog_inputs_fingerprint(
    cli_models: Sequence[Mapping[str, Any]],
    custom_models: Any,
) -> str:
    """Digest the inputs that decide the picker list, ignoring query and limit.

    Query-scoped reads must not look like content changes, so this hashes the
    sources rather than a built catalog.
    """

    payload = json.dumps(
        {
            "cli": [dict(model) for model in cli_models],
            "custom": custom_models,
        },
        ensure_ascii=True,
        sort_keys=True,
        default=str,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
