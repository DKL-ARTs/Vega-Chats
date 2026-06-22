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
        file_context = '\n\n[Attached files:]\n'
        for f in files:
            name = f.get('name', 'file')
            content = f.get('content', '')
            mime = f.get('mimeType', '')
            
            if mime.startswith('image/'):
                # For images, note that it's an image
                file_context += f'- {name} (image file, base64 length: {len(content)} chars)\n'
            else:
                # For other files, try to decode and show content
                try:
                    decoded = base64.b64decode(content).decode('utf-8', errors='ignore')
                    preview = decoded[:500] + ('...' if len(decoded) > 500 else '')
                    file_context += f'- {name} (content: {preview})\n'
                except:
                    file_context += f'- {name} (binary file, {len(content)} chars base64)\n'
        
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
