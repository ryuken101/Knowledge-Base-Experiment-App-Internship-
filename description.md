# Project Description — Knowledge Base (KB) App for the Task Agent

Build a per-user **knowledge base (KB)** with both a **Flutter frontend** and a
**SurrealDB backend**. The KB is the persistent memory for an AI agent that manages a
*separate* SurrealDB-backed **task manager** app, and it is also directly editable by a
human through the Flutter UI. The KB lives in the **same SurrealDB instance**
(`main` ns/db) as the task app and links to the task app's `user` table.

## Model

**One freeform markdown ("Obsidian") file per user.** There are no multiple documents
and no folder hierarchy. The agent reads/writes this file over MCP as its persistent
notes; the human edits it directly through the Flutter UI.

## Stack

- **Frontend:** Flutter + **go_router** (routing) + **riverpod** (state) + **dio** (HTTP).
- **Backend:** Python + **SurrealDB** SDK (direct calls, no ORM) + **MCP** (`FastMCP`) + **FastAPI** (REST for the Flutter app).
- **Agent interface:** MCP tools (stdio server), one tool per KB verb.

## Architecture

- `kb_program/` — client-agnostic **execution layer** (library only, no MCP/CLI imports):
  `KbCLI` (one method per verb), `db.py` client factory (signs in as **root**),
  `models.py` (`KnowledgeBase` + `KbError`).
- `kb_mcp/` — `FastMCP` server exposing one `@mcp.tool()` per `KbCLI` method; `KbError`
  is returned as `f"Error: {e}"`, never raised at the agent.
- `kb_api/` — FastAPI REST server the Flutter app talks to over **dio**, wrapping the
  same `KbCLI` execution layer.
- `kb_flutter/` — Flutter app (go_router / riverpod / dio). *(To be built.)*
- `schema.surql` / `reset.surql` — fresh-install schema (task tables + `knowledge_base`)
  and a record-wipe script.

---

## Front End (Flutter)

### Stage 1

- View and edit the single KB markdown file.
- **Left panel → table of contents** derived from the file's markdown headings
  (clicking a heading scrolls/jumps to that section).
- **Right panel → editor + preview** — switch between raw markdown editing and rendered
  preview.
- **Manual save** — changes are only persisted when the user explicitly saves.

### Stage 2

- Show **version history** for the KB file.
- **Load a previous version** from history.

### Stage 3

- Support **multiple users** (per-user KB, login).

---

## Back End

### Stage 1 — Single-file CRUD (done)

- `GET /knowledge-base` — read the KB (creates an empty one on first read).
- `PUT /knowledge-base` — replace the entire file (manual save).
- `PATCH /knowledge-base/append` — append a note on its own line.
- `DELETE /knowledge-base` — clear content (keeps the row).
- `DELETE /knowledge-base/lines/{n}` — delete a single line.
- `DELETE /knowledge-base/file` — delete the whole row.
- **Exactly one KB row per user**, enforced by a `UNIQUE` index on the `user` field.
- `created_at` set once; `updated_at` bumped explicitly on every write.
- **Single configurable user** for now (`KB_USER`, default `user:agent`); user record
  seeded on first write.

### Stage 2 — Version history

- New `knowledge_base_version` table, snapshotted on each save.
- API endpoints to **list versions** and **restore a previous version**.

### Stage 3 — Authentication / multiple users

- Real `user` records, login, and per-user access. The `record<user>` link + unique
  index already make this **purely additive**.
