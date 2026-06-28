import httpx
from app.config import settings
from fastapi import HTTPException


class OpenRouterProvider:
    name = 'openrouter'

    def __init__(self, api_key: str = None):
        key = api_key or settings.openrouter_api_key
        headers = {
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://vega-chat.app',
            'X-Title': 'Vega Chat',
        }
        if key and key.strip():
            headers['Authorization'] = 'Bearer ' + key.strip()
        self.client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers=headers,
            timeout=120.0,
        )

    async def chat(self, messages: list[dict], model: str = None, **kwargs) -> str:
        model = model or settings.default_model
        key = kwargs.get('api_key') or settings.openrouter_api_key
        if not key or not key.strip():
            raise HTTPException(status_code=400, detail=API
