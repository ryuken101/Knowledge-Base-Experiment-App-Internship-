# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A per-user **knowledge base (KB)** for an AI agent that manages a *separate*
SurrealDB-backed **task manager** app (the task app is **not in this repo** — it's
described in the project brief). The agent reads/writes it as persistent memory over
**MCP**; a Flutter app (`kb_flutter/`) is the human-facing editor.

Two KB surfaces share one execution layer:

- **Document tree** (`DocumentCLI`, `document` table) — ★ the primary surface. A nested
  **Notion/Outline-style** folder/document tree (added when the boss asked for "folders
  with nested documents"). Every node is a document; a *folder* is just a document with
  children. Each user sees their own **Personal** subtree (`owner = <user>`) plus a shared
  **Team** subtree (`owner = NONE`), both seeded on first use. Both the agent and the app
  navigate this same tree.
- **Single-file KB** (`KbCLI`, `knowledge_base` table) — the original "one freeform markdown
  ('Obsidian') file per user" design. Kept intact as legacy; don't extend by default.

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
  - `models.py` — `KnowledgeBase` + `Document` dataclasses + `KbError`.
  - `_common.py` — helpers shared by both CLIs: `query_rows` (SDK shape tolerance),
    `coerce_rid(value, table)` (string→`RecordID`, table-checked), `to_str`, `ensure_user`.
  - `program.py` — `KbCLI` (legacy single file): `get/set/append/clear_knowledge_base`
    (+ `delete_line`, `delete_knowledge_base`).
  - `documents.py` — `DocumentCLI` (the tree): `list_documents`, `read_document`,
    `create_document`, `update_document`, `move_document`, `delete_document`, plus
    `resolve_path`/`render_tree` for the agent's path-addressed MCP tools.
- `kb_mcp/` — `FastMCP` server (`server.py`): one `@mcp.tool()` per `KbCLI` method **and**
  the document-tree tools, via `_api()`/`_docs()` `lru_cache` singletons. `python -m kb_mcp`
  launches it (`__main__.py`).
- `kb_api/` — `FastAPI` REST server (`server.py`): `/knowledge-base*` routes + `/documents*`
  routes (the Flutter app's backend). `python -m kb_api` (port 8000).
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
- **Record ids are strings** like `user:agent`. `coerce_rid(value, table)` (in `_common.py`)
  coerces a string into a `RecordID`, raising `KbError` on a malformed or wrong-table id.
  Pass `RecordID` into `query` via `vars` — never string-interpolate ids into SurrealQL.
- **`query_rows`** (in `_common.py`) tolerates both SDK return shapes (rows returned directly
  vs. the older `{status, result}` envelope). Use it for `SELECT`.
- **Errors:** the execution layer raises `KbError`; the MCP layer catches it and returns
  `f"Error: {e}"` (the REST layer → HTTP 400) — it never raises out to the agent.

### Key behaviours and invariants (read before editing `documents.py`)

- **Unified tree, self-referenced.** `document.parent` is `option<record<document>>` (None =
  top-level). A folder is just a document with children; `is_folder` is a UI/type hint, not a
  structural constraint (so empty folders can exist and icons render).
- **Owner scoping = visibility, not security (yet).** `owner` is `option<record<user>>`:
  `<user>` for Personal, None for shared Team. `DocumentCLI` fetches **all** rows and filters
  `owner == user OR owner is None` **in Python** — single-user, so this is additive-ready
  structure, *not* a boundary. Move it to a `WHERE`/table `PERMISSIONS` when auth lands.
- **Create-on-read sections.** `list_documents` seeds a "Personal" (owned) and shared "Team"
  root folder if the user has none, mirroring `KbCLI`'s create-on-read.
- **Trees are assembled/walked in Python** from the flat row set (small per-user trees) — no
  recursive SurrealQL. Siblings order by `position`; **move/reorder renumbers the destination
  siblings 0..n** and **rejects cycles** (can't move a node into itself or a descendant).
  Moving across the Personal/Team boundary **cascades `owner`** to the moved subtree. Delete
  is a **subtree cascade**.
- **Path addressing for the agent.** MCP tools take slash-separated **title paths**
  (`Personal/Ideas/Roadmap`); `resolve_path` maps them to ids (case-insensitive).

### Schema (`kb_backend/schema.surql`)

`schema.surql` is a **complete fresh-install schema**: the task app's full schema verbatim
(`user`, `project`, `task`, `activity`, `comment` + their indexes) **plus** the
`knowledge_base` table **and** the `document` table (self-referencing `parent`, optional
`owner`, `is_folder`, `position`, with `document_parent`/`document_owner` indexes). Importing
it into an empty SurrealDB gives a working tasks + KB + document-tree environment with no
prior import needed. Every statement is `DEFINE ... IF NOT EXISTS` (idempotent), so it's also
safe against an instance that already has the task tables. When the task app's own schema
changes, **keep the copied task tables here in sync**.

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
- **Adding a DocumentCLI method/field:** add it to `documents.py` (return
  `_normalize(..., include_content=...)`); a new field also goes on the `document` DEFINE in
  `schema.surql`, `_normalize`, the `Document` dataclass, the Flutter `Document` model, and
  the `DocumentOut` pydantic model. Expose it both as a path-addressed `@mcp.tool()`
  (`kb_mcp`) and a `/documents*` route (`kb_api`). Owner-scope every read.
- **Flutter app (`kb_flutter/`):** the document tree lives in `lib/widgets/
  document_tree_panel.dart` (+ `_row`), `lib/providers/document_providers.dart`,
  `lib/api/document_api.dart`, `lib/models/document.dart`; the editor binds to the selected
  doc in `lib/screens/home_screen.dart`. Run `flutter analyze` after edits. The legacy
  single-file widgets (`kb_providers`, `kb_client`, `toc_panel`) remain but are unused.
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

Done: the **document tree** (nested folders/documents) and the **Flutter frontend**
(go_router/riverpod/dio) over it. Next — Stage 2: a `*_version` table +
`list_versions`/`restore_version`. Stage 3: **real multi-user auth** — turn the `owner`
field from in-code visibility filtering into genuine per-owner Personal sections and an
access-controlled Team area via table `PERMISSIONS` (the `record<user>` links already model
it). Also planned: drag-move/search polish in the tree, and folding `kb_program`/`kb_mcp`
into the task app for a single MCP surface.
