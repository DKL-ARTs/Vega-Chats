import json
import base64
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
    files = body.get('files', [])
    
    # Get API key from Authorization header or body
    api_key = None
    auth_header = request.headers.get('authorization', '')
    print(f'[AUTH] header=|{auth_header}| len={len(auth_header)} bytes={auth_header.encode("utf-8")}')
    if auth_header.startswith('Bearer '):
        raw_key = auth_header[7:]
        # Remove all whitespace and control chars
        cleaned = ''
        for ch in raw_key:
            if ch.isalnum() or ch in '-_.':
                cleaned += ch
        print(f'[AUTH] raw_key=|{raw_key}| cleaned=|{cleaned}|')
        if len(cleaned) >= 20:
            api_key = cleaned
    elif 'api_key' in body:
        api_key = body['api_key']
    
    print(f'[AUTH] final api_key_len={len(api_key) if api_key else 0}')
    
    provider = get_provider(provider_name)
    
    async def event_generator():
        try:
            async for chunk in provider.stream(messages, model, api_key=api_key):
                yield f'data: {chunk}\n\n'
        except Exception as e:
            yield f'data: Error: {str(e)}\n\n'
        yield 'data: [DONE]\n\n'
    
    return StreamingResponse(
        event_generator(),
        media_type='text/event-stream',
        headers={'Cache-Control': 'no-cache', 'Connection': 'keep-alive'},
    )
