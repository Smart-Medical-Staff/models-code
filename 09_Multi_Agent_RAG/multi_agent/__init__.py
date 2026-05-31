# multi_agent/__init__.py
# DiagnosticGraph.initialize is dynamically loaded from .graph
from .state import MultiAgentState


def __getattr__(name: str):
    if name == "DiagnosticGraph":
        from .graph import DiagnosticGraph
        return DiagnosticGraph
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = ["MultiAgentState", "DiagnosticGraph"]
