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
    for f in files:
        print(f'[DEBUG] File: {f.get("name")}, size={len(f.get("content", ""))}')
    
    # Add file info to messages for AI context
    if files:
        file_context = '\n\n[Attached files:]\n'
        for f in files:
            name = f.get('name', 'file')
            is_image = f.get('mimeType', '').startswith('image/')
            if is_image:
                file_context += f'- {name} (image)\n'
            else:
                file_context += f'- {name} (file)\n'
        
        # Add to last user message
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                msg['content'] = msg.get('content', '') + file_context
                break
    
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
