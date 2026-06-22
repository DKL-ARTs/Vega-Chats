import json
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
    
    print(f'[DEBUG] model={model}, messages={len(messages)}, files={len(files)}')
    
    # Add file info to last user message
    if files and messages:
        for f in files:
            name = f.get('name', 'file')
            messages[-1]['content'] += f'\n[File: {name}]'
    
    provider = get_provider(provider_name)
    
    async def event_generator():
        try:
            async for chunk in provider.stream(messages, model):
                yield f'data: {chunk}\n\n'
        except Exception as e:
            yield f'data: Error: {str(e)}\n\n'
        yield 'data: [DONE]\n\n'
    
    return StreamingResponse(
        event_generator(),
        media_type='text/event-stream',
        headers={'Cache-Control': 'no-cache', 'Connection': 'keep-alive'},
    )
