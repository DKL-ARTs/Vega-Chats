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
    
    print(f'[DEBUG] model={model}, messages={len(messages)}, files={len(files)}')
    
    # Add file content to messages for AI context
    if files:
        file_context = '\n\n[User attached files:]\n'
        for f in files:
            name = f.get('name', 'file')
            content = f.get('content', '')
            
            # Try to decode and show text content
            try:
                decoded = base64.b64decode(content).decode('utf-8', errors='ignore')
                preview = decoded[:1000] + ('...' if len(decoded) > 1000 else '')
                file_context += f'\n--- File: {name} ---\n{preview}\n--- End ---\n'
            except:
                file_context += f'\n--- File: {name} ({len(content)} chars) ---\n'
        
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
