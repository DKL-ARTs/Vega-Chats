
import json
import asyncio
import httpx
from .base import BaseProvider
from app.config import settings

class OpenRouterProvider(BaseProvider):
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
        import sys
        print(f"[STREAM] ENTERED api_key_len={len(api_key) if api_key else 0}", file=sys.stderr)
        model = model or settings.default_model
        key = api_key or settings.openrouter_api_key
        # Always create fresh client with proper headers
        client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers={
                'Authorization': 'Bearer ' + key,
                'Content-Type': 'application/json',
            },
            timeout=120.0,
        )
        print(f'[OpenRouter] Using model: {model} key_len={len(key) if key else 0}')
        print(f"[STREAM] settings_key={repr(settings.openrouter_api_key[:8])}", file=sys.stderr)
        print(f'[OpenRouter] api_key_param={api_key is not None} settings_key_len={len(settings.openrouter_api_key) if settings.openrouter_api_key else 0}')
        print(f"[OpenRouter] key_start={repr(key[:8]) if key else None}")
        _req_auth = client.headers.get("authorization", "")
        print(f"[SENDING] auth={_req_auth}", file=sys.stderr)
        buffer = []
        buffer_len = 0
        last_flush = asyncio.get_event_loop().time()
        FLUSH_SIZE = 40
        FLUSH_INTERVAL = 0.15
        async def flush():
            nonlocal buffer, buffer_len, last_flush
            if buffer:
                yield ''.join(buffer)
                buffer = []
                buffer_len = 0
                last_flush = asyncio.get_event_loop().time()
        try:
            print(f'[OR] About to call stream POST', file=sys.stderr)
            print("[OR] Stream call started, waiting for response...", file=sys.stderr)
            print('[OR] Using POST instead of stream', file=sys.stderr)
            or_resp = await self.client.post('/chat/completions', json={
                'model': model,
                'messages': messages,
                'stream': True,
                **kwargs,
            resp = await self.client.post(/chat/completions, json={
                model: model,
                messages: messages,
                stream: True,
                **kwargs,
            })
            print(f"[OR] Got response status={resp.status_code}", file=sys.stderr)
                if resp.status_code != 200:
                    error_text = await resp.aread()
                    yield f'Error: HTTP {resp.status_code}'
                    return
                async for line in resp.aiter_lines():
                    if line.startswith('data: '):
                        chunk = line[6:]
                        if chunk == '[DONE]':
                            if buffer:
                                yield ''.join(buffer)
                            return
                        try:
                            data = json.loads(chunk)
                            delta = data['choices'][0].get('delta', {})
                            content_delta = delta.get('content', '')
                            if content_delta:
                                buffer.append(content_delta)
                                buffer_len += len(content_delta)
                                now = asyncio.get_event_loop().time()
                                # Flush if buffer is large enough or enough time passed
                                if buffer_len >= FLUSH_SIZE or (now - last_flush) >= FLUSH_INTERVAL:
                                    yield ''.join(buffer)
                                    buffer = []
                                    buffer_len = 0
                                    last_flush = now
                        except (json.JSONDecodeError, KeyError, IndexError):
                            continue
        except Exception as e:
            yield f'Error: {str(e)}'


