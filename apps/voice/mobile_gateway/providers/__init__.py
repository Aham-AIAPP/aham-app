"""Processing providers.

A provider is the service that signs users in, turns uploaded audio into
transcripts and summaries, and serves them back. The phone app never talks to a
provider directly, so a provider can be replaced without changing the app.

A provider implements the methods of Provider. When it finishes a recording it
calls app.finish_upload(upload_id, result) with at least `recording_id`; the
gateway then marks the upload done and sends the push notification.
"""
from __future__ import annotations

import importlib


class Provider:
    name = 'base'

    def install(self, app):
        """Add provider-specific routes, e.g. for a worker that pulls uploads."""

    def login(self, username: str, password: str) -> dict:
        """Check credentials. Return {'id', 'name'}; raise HTTPException on failure."""
        raise NotImplementedError

    def upload_ready(self, upload: dict) -> None:
        """Called once an upload is complete and verified. Push-style providers send it here;
        pull-style providers (the worker fetches ready uploads) do nothing."""

    def recordings(self, user: dict, args: dict) -> dict:
        """List the user's recordings: {'items': [...], 'has_more', 'next_offset'}."""
        raise NotImplementedError

    def recording_part(self, user: dict, recording_id: str, part: str, args: dict) -> dict:
        """Return 'summary', 'transcript' or 'detail' of one recording."""
        raise NotImplementedError


PROVIDERS = {'aham_voice': 'aham_voice'}


def load_provider(name: str) -> Provider:
    if name not in PROVIDERS:
        raise RuntimeError(f'未知的处理服务：{name}')
    module = importlib.import_module(f'{__name__}.{PROVIDERS[name]}')
    return module.provider()
