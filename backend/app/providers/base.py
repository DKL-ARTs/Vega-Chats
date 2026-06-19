from abc import ABC, abstractmethod
from typing import AsyncIterator

class BaseProvider(ABC):
    name: str = "base"
    
    @abstractmethod
    async def chat(self, messages: list[dict], model: str, **kwargs) -> str:
        pass
    
    @abstractmethod
    async def stream(self, messages: list[dict], model: str, **kwargs) -> AsyncIterator[str]:
        pass
