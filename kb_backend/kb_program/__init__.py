"""Knowledge-base execution layer. Client-agnostic (no MCP/CLI imports)."""
from .models import KbError, KnowledgeBase
from .program import KbCLI

__all__ = ["KbCLI", "KbError", "KnowledgeBase"]
