"""FastMCP server exposing the knowledge base to the agent.

One @mcp.tool() per active KbCLI method, via a lazily-built _api() singleton.
KbError is returned as `f"Error: {e}"` instead of raised — the agent sees a
structured string, never a traceback. Mirrors the task app's task_mcp/server.py.

When the KB is later folded into the task app, these become additional tools on
the existing task MCP so the agent sees tasks + KB through one server.
"""
from __future__ import annotations

from functools import lru_cache

from mcp.server.fastmcp import FastMCP

from kb_program import DocumentCLI, KbCLI, KbError

mcp = FastMCP("knowledge-base")


@lru_cache(maxsize=1)
def _api() -> KbCLI:
    return KbCLI()


@lru_cache(maxsize=1)
def _docs() -> DocumentCLI:
    return DocumentCLI()


@mcp.tool()
def get_knowledge_base() -> str:
    """Return the agent's knowledge base as markdown. The KB is the agent's
    persistent notes about how to manage this user's tasks; read it before
    acting. Creates an empty KB on first read."""
    try:
        return _api().get_knowledge_base()["content"]
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def set_knowledge_base(content: str) -> str:
    """Replace the entire knowledge base with `content` (markdown). Overwrites
    everything — use append_knowledge_base to add a single note without losing
    the existing contents."""
    try:
        _api().set_knowledge_base(content)
        return "Knowledge base saved."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def append_knowledge_base(text: str) -> str:
    """Append `text` to the knowledge base on its own line, preserving existing
    contents. Use this to record a new observation or preference."""
    try:
        _api().append_knowledge_base(text)
        return "Note appended to knowledge base."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def clear_knowledge_base() -> str:
    """Empty the knowledge base (keeps the record but removes all content)."""
    try:
        _api().clear_knowledge_base()
        return "Knowledge base cleared."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def delete_knowledge_base_line(line_number: int) -> str:
    """Delete a single line (1-based) from the knowledge base, keeping the rest.
    Use this to remove one stale note without rewriting the whole file."""
    try:
        _api().delete_line(line_number)
        return f"Deleted line {line_number}."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def delete_knowledge_base() -> str:
    """Delete the entire knowledge base file (the whole record), not just its
    content. A later get_knowledge_base recreates an empty one."""
    try:
        _api().delete_knowledge_base()
        return "Knowledge base deleted."
    except KbError as e:
        return f"Error: {e}"


# ---- document tree ------------------------------------------------------
#
# The agent navigates the same nested folder/document tree the human sees in the
# app. Documents are addressed by a slash-separated title path
# (e.g. `Personal/Ideas/Roadmap`); a "folder" is just a document that holds
# children. Each user sees their own `Personal` subtree plus the shared `Team`
# subtree, both seeded on first use.


@mcp.tool()
def list_documents() -> str:
    """Show the document tree (folders + documents) as indented text. Read this
    to discover what documents exist and their paths before reading or writing
    one. Each line is a node; nesting shows the folder structure."""
    try:
        return _docs().render_tree()
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def read_document(path: str) -> str:
    """Return a document's markdown content. `path` is a slash-separated title
    path, e.g. `Personal/Ideas/Roadmap`. Use list_documents to see valid paths."""
    try:
        doc_id = _docs().resolve_path(path)
        return _docs().read_document(doc_id)["content"]
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def write_document(path: str, content: str) -> str:
    """Replace the markdown content of the document at `path` (slash-separated
    title path). Overwrites the whole document's content."""
    try:
        doc_id = _docs().resolve_path(path)
        _docs().update_document(doc_id, content=content)
        return f"Wrote {path}."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def create_document(title: str, parent_path: str = "", is_folder: bool = False) -> str:
    """Create a new document (or folder if `is_folder`) titled `title`. Place it
    inside the folder at `parent_path` (slash-separated title path), or leave
    `parent_path` empty to create it at the top level of your Personal area."""
    try:
        parent_id = _docs().resolve_path(parent_path) if parent_path.strip() else None
        _docs().create_document(title=title, parent_id=parent_id, is_folder=is_folder)
        kind = "folder" if is_folder else "document"
        where = f" in {parent_path}" if parent_path.strip() else ""
        return f"Created {kind} '{title}'{where}."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def rename_document(path: str, title: str) -> str:
    """Rename the document at `path` (slash-separated title path) to `title`."""
    try:
        doc_id = _docs().resolve_path(path)
        _docs().update_document(doc_id, title=title)
        return f"Renamed {path} to '{title}'."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def move_document(path: str, new_parent_path: str = "", index: int = 0) -> str:
    """Move the document at `path` into the folder at `new_parent_path` (both
    slash-separated title paths), positioned at `index` among its new siblings.
    Leave `new_parent_path` empty to move it to the top level."""
    try:
        doc_id = _docs().resolve_path(path)
        new_parent_id = _docs().resolve_path(new_parent_path) if new_parent_path.strip() else None
        _docs().move_document(doc_id, new_parent_id=new_parent_id, index=index)
        return f"Moved {path}."
    except KbError as e:
        return f"Error: {e}"


@mcp.tool()
def delete_document(path: str) -> str:
    """Delete the document at `path` (slash-separated title path) and everything
    nested inside it. This cannot be undone."""
    try:
        doc_id = _docs().resolve_path(path)
        res = _docs().delete_document(doc_id)
        return f"Deleted {path} ({res['count']} document(s))."
    except KbError as e:
        return f"Error: {e}"


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
