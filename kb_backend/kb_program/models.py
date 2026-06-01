"""Dataclasses and error type for the knowledge-base backend.

Ids are strings (SurrealDB record ids like `knowledge_base:abc` / `user:xyz`),
mirroring the task app's models.
"""
from __future__ import annotations

from dataclasses import dataclass


class KbError(Exception):
    """Raised on validation or not-found failures in KbCLI."""


@dataclass
class KnowledgeBase:
    """One freeform markdown ("Obsidian") file owned by a user."""

    user_id: str | None = None
    content: str = ""
    created_at: str | None = None
    updated_at: str | None = None
