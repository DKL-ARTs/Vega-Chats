import json
import sys
from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse
from app.providers import get_provider

router = APIRouter()

@router.post('/chat/stream')
async def chat_stream(request: Request):
    body = await request.json()
    messages = body.get('messages', [])
    model = body.get('model', 'openrouter/auto')
    provider_name = body.get('provider', 'openrouter')

    api_key = None
    auth_header = request.headers.get('authorization', '')
    if auth_header.startswith('Bearer '):
        raw_key = auth_header[7:]
        cleaned = ''.join(ch for ch in raw_key if ch.isalnum() or ch in '-_.')
        if len(cleaned) >= 20:
            api_key = cleaned

    provider = get_provider(provider_name)
    complete_text = ''
    chunk_count = 0

    async for chunk in provider.stream(messages, model, api_key=api_key):
        chunk_count += 1
        print(f'[SSE] chunk #{chunk_count}: {repr(chunk[:150])}', file=sys.stderr)
        if not chunk or chunk == '[DONE]':
            continue
        json_str = chunk
        if json_str.startswith('data: '):
            json_str = json_str[6:]
        elif json_str.startswith('data:'):
            json_str = json_str[5:]
        json_str = json_str.strip()
        if not json_str or json_str == '[DONE]':
            continue
        try:
            data = json.loads(json_str)
            choices = data.get('choices', [])
            if choices:
                delta = choices[0].get('delta', {})
                content = delta.get('content', '')
                if content:
                    complete_text += content
        except (json.JSONDecodeError, KeyError, IndexError):
            complete_text += chunk

    print(f'[SSE] Total chunks: {chunk_count}, final text len: {len(complete_text)}', file=sys.stderr)
    return StreamingResponse(iter([complete_text]), media_type='text/plain')
