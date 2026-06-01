"""FastAPI server exposing the knowledge base as a simple REST CRUD API.

A thin client over KbCLI, mirroring kb_mcp/server.py: a lazily-built _api()
singleton wraps the execution layer, and every route delegates to one KbCLI
method. KbError is surfaced as an HTTP 400 (the REST analog of kb_mcp's
`return f"Error: {e}"`) so callers get a structured error, never a traceback.

Single-user for now: every route operates on the configured KB_USER (default
`user:agent`); no user_id is accepted. Only the `knowledge_base` table is
touched (plus the seed-on-first-write `user` row KbCLI already creates).

    pip install -e ".[api]"
    python -m kb_api            # serves on 127.0.0.1:8000, Swagger at /docs
"""
from __future__ import annotations

import os
from functools import lru_cache

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from kb_program import KbCLI, KbError

app = FastAPI(
    title="knowledge-base",
    description="Per-user markdown knowledge base, backed by SurrealDB.",
    version="0.1.0",
)

# CORS so the Flutter web build (served from a different origin) can call the API.
# Wide open for single-user dev; tighten allow_origins when auth lands (Stage 3).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@lru_cache(maxsize=1)
def _api() -> KbCLI:
    return KbCLI()


# ---- schemas -------------------------------------------------------------


class SetRequest(BaseModel):
    content: str


class AppendRequest(BaseModel):
    text: str


class KnowledgeBaseOut(BaseModel):
    user_id: str | None = None
    content: str = ""
    created_at: str | None = None
    updated_at: str | None = None


class DeleteResult(BaseModel):
    user_id: str | None = None
    deleted: bool = False


# ---- routes --------------------------------------------------------------


@app.get("/knowledge-base", response_model=KnowledgeBaseOut)
def read_knowledge_base() -> dict:
    """Return the knowledge base. Creates an empty one on first read."""
    try:
        return _api().get_knowledge_base()
    except KbError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.put("/knowledge-base", response_model=KnowledgeBaseOut)
def replace_knowledge_base(body: SetRequest) -> dict:
    """Replace the entire knowledge base with `content` (markdown)."""
    try:
        return _api().set_knowledge_base(body.content)
    except KbError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.patch("/knowledge-base/append", response_model=KnowledgeBaseOut)
def append_to_knowledge_base(body: AppendRequest) -> dict:
    """Append `text` to the knowledge base on its own line, keeping existing content."""
    try:
        return _api().append_knowledge_base(body.text)
    except KbError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.delete("/knowledge-base", response_model=KnowledgeBaseOut)
def clear_knowledge_base() -> dict:
    """Empty the knowledge base content (keeps the row and created_at)."""
    try:
        return _api().clear_knowledge_base()
    except KbError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.delete("/knowledge-base/lines/{line_number}", response_model=KnowledgeBaseOut)
def delete_knowledge_base_line(line_number: int) -> dict:
    """Delete a single line (1-based) from the knowledge base, keeping the rest."""
    try:
        return _api().delete_line(line_number)
    except KbError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.delete("/knowledge-base/file", response_model=DeleteResult)
def delete_knowledge_base_file() -> dict:
    """Delete the entire knowledge base markdown file (the whole row), not just
    its content. A later GET recreates an empty one (create-on-read)."""
    try:
        return _api().delete_knowledge_base()
    except KbError as e:
        raise HTTPException(status_code=400, detail=str(e))


def main() -> None:
    import uvicorn

    host = os.getenv("KB_API_HOST", "127.0.0.1")
    port = int(os.getenv("KB_API_PORT", "8000"))
    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":
    main()
