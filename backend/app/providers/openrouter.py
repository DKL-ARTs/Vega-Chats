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
    
    def _extract_content(self, data):
        """Extract text content from various response formats"""
        try:
            choices = data.get('choices', [])
            if not choices:
                return ''
            delta = choices[0].get('delta', {})
            content = delta.get('content', '')
            # If content is a JSON string, try to parse it
            if isinstance(content, str) and content.startswith('{'):
                try:
                    parsed = json.loads(content)
                    if 'content' in parsed:
                        return parsed['content']
                    if 'text' in parsed:
                        return parsed['text']
                except:
                    pass
            return content if isinstance(content, str) else ''
        except:
            return ''
    
    async def stream(self, messages: list[dict], model: str = None, **kwargs):
        model = model or settings.default_model
        print(f'[OpenRouter] Using model: {model}')
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
                            return
                        try:
                            data = json.loads(chunk)
                            content = self._extract_content(data)
                            if content:
                                yield content
                        except json.JSONDecodeError:
                            continue
        except Exception as e:
            yield f'Error: {str(e)}'
