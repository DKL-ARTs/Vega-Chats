import json
import asyncio
import httpx
from .base import BaseProvider
from app.config import settings

class OpenRouterProvider(BaseProvider):
    name = 'openrouter'
    
    def __init__(self):
        self.client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers={
                'Authorization': f'Bearer {settings.openrouter_api_key}',
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
    
    async def stream(self, messages: list[dict], model: str = None, **kwargs):
        model = model or settings.default_model
        print(f'[OpenRouter] Using model: {model}')
        buffer = ''
        last_send = asyncio.get_event_loop().time()
        try:
            async with self.client.stream('POST', '/chat/completions', json={
                'model': model,
                'messages': messages,
                'stream': True,
                **kwargs,
            }) as resp:
                if resp.status_code != 200:
                    error_text = await resp.aread()
                    yield f'Error: HTTP {resp.status_code}'
                    return
                async for line in resp.aiter_lines():
                    if line.startswith('data: '):
                        chunk = line[6:]
                        if chunk == '[DONE]':
                            if buffer:
                                yield buffer
                            return
                        try:
                            data = json.loads(chunk)
                            delta = data['choices'][0].get('delta', {})
                            content = delta.get('content', '')
                            if content:
                                buffer += content
                                now = asyncio.get_event_loop().time()
                                # Send if buffer is large enough or enough time passed
                                if len(buffer) > 50 or (now - last_send) > 0.5:
                                    yield buffer
                                    buffer = ''
                                    last_send = now
                        except (json.JSONDecodeError, KeyError, IndexError):
                            continue
                if buffer:
                    yield buffer
        except Exception as e:
            yield f'Error: {str(e)}'
