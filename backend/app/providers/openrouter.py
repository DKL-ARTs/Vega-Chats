import json
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
    
    def _extract_content(self, data):
        try:
            choices = data.get('choices', [])
            if not choices:
                return ''
            delta = choices[0].get('delta', {})
            content = delta.get('content', '')
            if not isinstance(content, str):
                return ''
            if content.startswith('{'):
                try:
                    parsed = json.loads(content)
                    if 'choices' in parsed:
                        inner_delta = parsed['choices'][0].get('delta', {})
                        inner_content = inner_delta.get('content', '')
                        if inner_content:
                            return inner_content
                    if 'content' in parsed:
                        return parsed['content']
                    if 'text' in parsed:
                        return parsed['text']
                except:
                    pass
            return content
        except:
            return ''
    
    async def stream(self, messages: list[dict], model: str = None, **kwargs):
        model = model or settings.default_model
        print(f'[OpenRouter] Using model: {model}')
        buffer = ''
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
                            content = self._extract_content(data)
                            if content:
                                buffer += content
                                # Send when we have enough content or at natural break points
                                if len(buffer) >= 20 or buffer.endswith('. ') or buffer.endswith('! ') or buffer.endswith('? ') or buffer.endswith('\n'):
                                    yield buffer
                                    buffer = ''
                        except json.JSONDecodeError:
                            continue
                if buffer:
                    yield buffer
        except Exception as e:
            yield f'Error: {str(e)}'
