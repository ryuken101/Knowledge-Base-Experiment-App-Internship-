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

from kb_program import KbCLI, KbError

mcp = FastMCP("knowledge-base")


@lru_cache(maxsize=1)
def _api() -> KbCLI:
    return KbCLI()


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


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
