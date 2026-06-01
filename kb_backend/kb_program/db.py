"""Cached SurrealDB client for the knowledge-base backend.

Mirrors the task app's task_program/db.py: reads connection settings from a .env
file (discovered by walking up from cwd, then falling back to the legacy
~/.config/taskcli/.env), connects, and signs in as root. The client is lru_cached
so it is connected and signed in once per process.

Point this at the SAME SurrealDB instance as the task app — the KB reuses the
task app's `user` table.
"""
from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from dotenv import find_dotenv, load_dotenv
from surrealdb import Surreal


def _load_env() -> None:
    """Load .env from cwd-upwards, else the legacy ~/.config/taskcli/.env.

    The fallback dir name is the legacy `taskcli` (not `task`/`kb`) so a single
    .env shared with the task app is picked up unchanged.
    """
    found = find_dotenv(usecwd=True)
    if found:
        load_dotenv(found)
        return
    fallback = Path.home() / ".config" / "taskcli" / ".env"
    if fallback.is_file():
        load_dotenv(fallback)


@lru_cache(maxsize=None)
def client(
    url: str | None = None,
    username: str | None = None,
    password: str | None = None,
    namespace: str | None = None,
    database: str | None = None,
) -> Surreal:
    """Return a connected, signed-in Surreal client (cached per arg-set)."""
    _load_env()

    url = url or os.getenv("SURREALDB_URL")
    username = username or os.getenv("SURREALDB_USER")
    password = password or os.getenv("SURREALDB_PASS")
    namespace = namespace or os.getenv("SURREALDB_NS", "main")
    database = database or os.getenv("SURREALDB_DB", "main")

    if not (url and username and password):
        raise RuntimeError(
            "SURREALDB_URL, SURREALDB_USER and SURREALDB_PASS must be set"
        )

    db = Surreal(url)
    db.signin({"username": username, "password": password})
    db.use(namespace, database)
    return db
