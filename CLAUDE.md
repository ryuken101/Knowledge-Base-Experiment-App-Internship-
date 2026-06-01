# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A per-user **knowledge base (KB)** for an AI agent that manages a *separate*
SurrealDB-backed **task manager** app (the task app is **not in this repo** — it's
described in the project brief). Each user's agent gets one freeform markdown
("Obsidian") file it reads/writes as persistent memory, accessed over **MCP**.

Two code areas, only one active:

- **`kb_backend/`** — ★ ACTIVE. Python + SurrealDB + MCP. This is the real deliverable.
- **`KbApp/`** — ✗ LEGACY, superseded. A C# / ASP.NET Core + EF Core + SQLite prototype
  that modelled the KB as many `Document` records with folder paths. Dropped in favour of
  the single-markdown-file design in `kb_backend/`. Kept only for reference; not wired
  into anything. Don't extend it; don't delete without confirming.

The KB lives in the **same SurrealDB instance** (`main` namespace / `main` database) as
the task app and links to the task app's `user` table — so the agent that drives tasks
over MCP can also read/write its own KB.

## Architecture (`kb_backend/`)

Mirrors the task app's conventions: a client-agnostic **execution layer** plus thin
**clients** that wrap it. Direct SurrealDB SDK calls, **no ORM/repository layer**.

- `kb_program/` — execution layer (library only; no MCP/CLI imports).
  - `db.py` — `client()` factory, `lru_cache`d so SurrealDB connects + signs in **as root**
    once per process. Reads `SURREALDB_URL/USER/PASS/NS/DB` from `.env` via
    `find_dotenv(usecwd=True)`, falling back to `~/.config/taskcli/.env` (legacy folder name,
    shared with the task app). `Surreal(url)` is a **factory function**, not a class — it
    returns a blocking connection.
  - `models.py` — `KnowledgeBase` dataclass + `KbError`.
  - `program.py` — `KbCLI` with one method per verb: `get_knowledge_base`,
    `set_knowledge_base`, `append_knowledge_base`, `clear_knowledge_base`.
- `kb_mcp/` — `FastMCP` server (`server.py`), one `@mcp.tool()` per `KbCLI` method via an
  `_api()` `lru_cache` singleton. `python -m kb_mcp` launches it (`__main__.py`).
- `schema.surql` / `reset.surql` — see below.

### Key behaviours and invariants (read before editing `program.py`)

- **One KB row per user**, enforced by `DEFINE INDEX knowledge_base_user ... UNIQUE` on the
  `user` field. `KbCLI` guards against duplicates by fetching the existing row first.
- **Create-on-read.** `get_knowledge_base` creates an empty KB if none exists, so the
  agent always has a row to append to.
- **`updated_at` is bumped explicitly by the backend** on every write (the `UPDATE ... SET
  updated_at = time::now()` query), matching the task app's "no magic events" style.
  `created_at` is set once by the schema DEFAULT and stays fixed.
- **Single-user for now.** The `user` table is dead structure (no auth yet). The KB
  operates on one configurable user: pass `user_id`, or set `KB_USER` (default
  `user:agent`). The user record is **seeded on first write** so the `record<user>` link is
  backed by a real row. Multi-user is then purely additive — don't add user CRUD/auth
  without revisiting this.
- **Normalize all returns.** `_normalize` reproduces the dict contract
  `{user_id, content, created_at, updated_at}`: `RecordID`→str (`"user:agent"`),
  `datetime`→ISO string, `user` link renamed to `user_id`. The SDK decodes SurrealDB
  datetimes to **Python `datetime`** and links to **`RecordID`** on read — `_to_str` relies
  on that. Methods never return raw SDK rows.
- **Record ids are strings** like `user:agent`. `_user_rid` coerces a string into a
  `RecordID` (raising `KbError` on a malformed or wrong-table id). Pass `RecordID` into
  `query` via `vars` — never string-interpolate ids into SurrealQL.
- **`_query_rows`** tolerates both SDK return shapes (rows returned directly vs. the older
  `{status, result}` envelope). Use it for `SELECT`.
- **Errors:** the execution layer raises `KbError`; the MCP layer catches it and returns
  `f"Error: {e}"` — it never raises out to the agent.

### Schema (`kb_backend/schema.surql`)

`schema.surql` is a **complete fresh-install schema**: the task app's full schema verbatim
(`user`, `project`, `task`, `activity`, `comment` + their indexes) **plus** the
`knowledge_base` table. Importing it into an empty SurrealDB gives a working tasks + KB
environment with no prior import needed. Every statement is `DEFINE ... IF NOT EXISTS`
(idempotent), so it's also safe against an instance that already has the task tables. When
the task app's own schema changes, **keep the copied task tables here in sync**.

`reset.surql` deletes all records per table while keeping the schema (handy between tests).

Connection signs in as **root**, which bypasses table `PERMISSIONS` — the single-user
analog of "RLS off everywhere". The schema therefore needs no per-table permission lines.

## Commands

```bash
cd kb_backend
pip install -e ".[mcp]"        # execution layer + FastMCP server
python -m kb_mcp               # launch the MCP server (stdio)

python -m py_compile kb_program/*.py kb_mcp/*.py   # quick syntax check
```

**Import the schema** into SurrealDB (`main`/`main`) via the Surrealist query editor
(paste `schema.surql` → Run query) or `surreal import`.

### Testing without touching a live DB

There is no test suite yet. To exercise `KbCLI` end-to-end safely, use the SDK's embedded
**in-memory** engine and monkeypatch the client factory — this needs no credentials and
never writes to the real Surreal Cloud DB:

```python
from pathlib import Path
from surrealdb import Surreal
import kb_program.db as dbmod, kb_program.program as prog

mem = Surreal("mem://"); mem.use("main", "main")
mem.query(Path("schema.surql").read_text(encoding="utf-8"))
prog.client = dbmod.client = lambda *a, **k: mem   # program.py imports `client` by name

from kb_program import KbCLI
api = KbCLI(default_user="user:agent")
api.set_knowledge_base("# Notes")
print(api.get_knowledge_base()["content"])
```

(Run from inside `kb_backend/`.) Do **not** run write paths against the live Surreal Cloud
instance in `.env` without explicit confirmation.

## Conventions / gotchas

- **Adding a KbCLI method/field:** add the method to `program.py` (returning
  `_normalize(...)`); if a new field, add it to the `knowledge_base` DEFINE in
  `schema.surql` and to `_normalize`/`_KB_KEYS`; expose it as a `@mcp.tool()` in
  `kb_mcp/server.py` returning `f"Error: {e}"` on `KbError`. Keep `kb_program` free of
  MCP/CLI imports.
- **`.env.example` is a template** — real secrets belong only in a git-ignored `.env`. The
  backend uses **root** credentials with no table permissions, so the DB URL + creds grant
  full read/write; don't commit live secrets or expose the DB publicly without an auth layer.
- **Two READMEs:** root `README.md` is the narrative/architecture; `kb_backend/README.md`
  is the package quickstart. Keep them in sync when behaviour changes.

## Legacy `KbApp/` (reference only)

ASP.NET Core Web API, `net10.0`, EF Core + SQLite (`kb.db`). One `Document` entity
(`Title`, markdown `Content`, `FolderPath`, timestamps), CRUD at `/api/documents` plus
`/api/documents/folders`, Swagger in Development. Run with `dotnet run` from
`KbApp/KbApp.Api`. Superseded — prefer `kb_backend/` for all new work.

## Roadmap (schema kept additive-ready)

Stage 2: `knowledge_base_version` table + `list_versions`/`restore_version`. Stage 3: real
multi-user auth (the `record<user>` link + unique index already support it). Also planned:
a Flutter frontend (go_router/riverpod/dio) and folding `kb_program`/`kb_mcp` into the task
app for a single MCP surface.
