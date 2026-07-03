"""Knowledge-base execution layer. Client-agnostic (no MCP/CLI imports)."""
from .documents import DocumentCLI
from .models import Document, KbError, KnowledgeBase
from .program import KbCLI

__all__ = ["KbCLI", "DocumentCLI", "KbError", "KnowledgeBase", "Document"]
