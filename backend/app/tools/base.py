from abc import ABC, abstractmethod
from pydantic import BaseModel
from typing import Any

class ToolInput(BaseModel):
    pass

class BaseTool(ABC):
    name: str = "base"
    description: str = ""
    
    @abstractmethod
    async def execute(self, **kwargs) -> str:
        pass
    
    @abstractmethod
    def input_schema(self) -> dict:
        pass
