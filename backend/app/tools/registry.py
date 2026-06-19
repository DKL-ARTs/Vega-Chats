from typing import Optional
from .base import BaseTool

_tools: dict[str, BaseTool] = {}

def register(tool: BaseTool):
    _tools[tool.name] = tool

def get(name: str) -> Optional[BaseTool]:
    return _tools.get(name)

def list_tools() -> list[dict]:
    return [{"name": t.name, "description": t.description, "schema": t.input_schema()} for t in _tools.values()]
