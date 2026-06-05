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


@dataclass
class Document:
    """A node in the document tree. A folder is just a document that holds
    children (is_folder is a UI/type hint). `parent_id` is None for a top-level
    node; `owner_id` is None for a shared (Team) node, else the owning user.
    `content` is omitted (None) from list results and populated by read."""

    id: str | None = None
    title: str = "Untitled"
    parent_id: str | None = None
    owner_id: str | None = None
    is_folder: bool = False
    position: int = 0
    content: str | None = None
    created_at: str | None = None
    updated_at: str | None = None
