# Project Description — Knowledge Base (KB) App for the Task Agent

Build a per-user **knowledge base (KB)** with both a **Flutter frontend** and a
**SurrealDB backend**. The KB is the persistent memory for an AI agent that manages a
*separate* SurrealDB-backed **task manager** app, and it is also directly editable by a
human through the Flutter UI. The KB lives in the **same SurrealDB instance**
(`main` ns/db) as the task app and links to the task app's `user` table.

> **Scope change (this revision):** the frontend is no longer a roadmap item — it is now
> in scope and built to the **original KbApp frontend spec**: a directory of markdown
> documents with **nested folders** and a two-panel (directory / document) layout.
> Delivering that requires the backend to move from the current **single markdown file
> per user** to a **multi-document + folder** model (see Backend → Stage 1). The single
> agent-facing markdown file (read/written over MCP) is preserved alongside the new
> document tree.

## Stack

- **Frontend:** Flutter + **go_router** (routing) + **riverpod** (state) + **dio** (HTTP).
- **Backend:** Python + **SurrealDB** SDK (direct calls, no ORM) + **MCP** (`FastMCP`).
- **Agent interface:** MCP tools (stdio server), one tool per KB verb.

## Architecture

- `kb_program/` — client-agnostic **execution layer** (library only, no MCP/CLI imports):
  `KbCLI` (one method per verb), `db.py` client factory (signs in as **root**),
  `models.py` (`KnowledgeBase` + `KbError`).
- `kb_mcp/` — `FastMCP` server exposing one `@mcp.tool()` per `KbCLI` method; `KbError`
  is returned as `f"Error: {e}"`, never raised at the agent.
- `kb_api/` — HTTP API (REST) the Flutter app talks to over **dio**, wrapping the same
  `KbCLI` execution layer. *(New — needed because Flutter can't speak MCP.)*
- `kb_flutter/` — Flutter app (go_router / riverpod / dio). *(New.)*
- `schema.surql` / `reset.surql` — fresh-install schema (task tables + KB tables) and a
  record-wipe script.

---

## Front End (Flutter)

### Stage 1

- Create a KB document in **markdown** format.
- View **all KB documents** in a directory.
- Support **nested folders** for the KB directory.
- Create / edit documents in markdown.
- Allow **manual save** of changes by the user.
- View documents as **doc previews** (rendered markdown).
- **Left panel → directory** (folder/document tree).
- **Right panel → current document** (editor + preview).

### Stage 2

- Show **version history** for a document.
- **Load a previous version** from history.

### Stage 3

- Support **multiple users** (per-user directories, login).

---

## Back End

### Stage 1 — Documents + folders (CRUD API)

- **CRUD API for documents** (consumed by the Flutter app over dio, and exposed as MCP
  tools for the agent).
- Store documents in SurrealDB with appropriate **indexes** (e.g. on `user`, `folder_path`).
- A `document` table: `title`, markdown `content`, `folder_path`, `user`,
  `created_at`/`updated_at`. Nested folders are modelled by `folder_path`
  (e.g. `notes/projects/acme`).
- `updated_at` bumped explicitly by the backend on every write; `created_at` set once.
- **Agent-facing single markdown file is preserved**: the existing `knowledge_base`
  table + `get/set/append/clear` MCP tools remain so the agent keeps one freeform memory
  file. (Open question: whether the agent's file becomes one designated document in the
  tree, or stays a separate row — decide before implementing.)
- **Single configurable user** for now (the `user` table is dead structure / no auth):
  pass `user_id` or set `KB_USER` (default `user:agent`); the user record is seeded on
  first write so the `record<user>` link is backed by a real row.
- Connection signs in as **root** (bypasses table permissions — the single-user analog
  of "RLS off").

### Stage 2 — Version history

- CRUD for **version history**: a `document_version` table snapshotted on each save.
- API/tools to **list versions** and **restore / load a previous version**.

### Stage 3 — Authentication / multiple users

- Real `user` records, login, and per-user access to documents. The `record<user>` link
  + indexes already make this **purely additive** — don't add user CRUD/auth without
  revisiting the single-user assumptions in `KbCLI`.
