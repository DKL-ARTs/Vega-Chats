import httpx
from app.config import settings


class OpenRouterProvider:
    name = 'openrouter'

    def __init__(self, api_key: str = None):
        key = api_key or settings.openrouter_api_key
        self.client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers={
                'Authorization': f'Bearer {key}',
                'Content-Type': 'application/json',
            },
            timeout=120.0,
        )

    async def chat(self, messages: list[dict], model: str = None, **kwargs) -> str:
        model = model or settings.default_model
        resp = await self.client.post('/chat/completions', json={
            'model': model,
            'messages': messages,
            **kwargs,
        })
        resp.raise_for_status()
        data = resp.json()
        return data['choices'][0]['message']['content']

    async def stream(self, messages: list[dict], model: str = None, api_key: str = None, **kwargs):
        model = model or settings.default_model
        key = api_key or settings.openrouter_api_key
        client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers={
                'Authorization': 'Bearer ' + key,
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://vega-chat.app',
                'X-Title': 'Vega Chat',
            },
            timeout=120.0,
        )
        try:
            resp = await client.post('/chat/completions', json={
                'model': model,
                'messages': messages,
                'stream': True,
                **kwargs,
            })
            if resp.status_code != 200:
                error_text = await resp.aread()
                yield f'Error: HTTP {resp.status_code}: {error_text[:200]}'
                return
            async for line in resp.aiter_lines():
                if line:
                    yield line
        except Exception as e:
            yield f'Error: {str(e)}'
