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
   
    api_key = None
    auth_header = request.headers.get('authorization', '')
    if auth_header.startswith('Bearer '):
        raw_key = auth_header[7:]
        cleaned = ''
        for ch in raw_key:
            if ch.isalnum() or ch in '-_.':
                cleaned += ch
        if len(cleaned) >= 20:
            api_key = cleaned
    elif 'api_key' in body:
        api_key = body['api_key']
    
    provider = get_provider(provider_name)
    
    # Collect all text from SSE stream
    complete_text = ''
    async for chunk in provider.stream(messages, model, api_key=api_key):
        if chunk.startswith('data: ') or chunk.startswith('data:'):
            json_str = chunk
            if json_str.startswith('data: '):
                json_str = json_str[6:]
            elif json_str.startswith('data:'):
                json_str = json_str[5:]
            json_str = json_str.strip()
            if json_str and json_str != '[DONE]':
                try:
                    data = json.loads(json_str)
                    choices = data.get('choices', [])
                    if choices:
                        delta = choices[0].get('delta', {})
                        content = delta.get('content', '')
                        if content:
                            complete_text += content
                except (json.JSONDecodeError, KeyError, IndexError):
                    pass
        else:
            complete_text += chunk
    
    return StreamingResponse(
        iter([complete_text]),
        media_type='text/plain',
    )

