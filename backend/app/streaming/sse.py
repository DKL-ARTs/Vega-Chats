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
    files = body.get('files', [])  # List of {name, content_base64}
    
    print(f'[DEBUG] Stream request: model={model}, messages={len(messages)}, files={len(files)}')
    
    # If files attached, add them to the last user message
    if files and messages:
        last_msg = messages[-1]
        if last_msg.get('role') == 'user':
            file_descriptions = []
            for f in files:
                name = f.get('name', 'file')
                size = len(f.get('content', '')) if f.get('content') else 0
                file_descriptions.append(f'File: {name} ({size} bytes)')
            last_msg['content'] = last_msg.get('content', '') + '\n' + '\n'.join(file_descriptions)
    
    provider = get_provider(provider_name)
    
    async def event_generator():
        chunk_count = 0
        try:
            async for chunk in provider.stream(messages, model):
                chunk_count += 1
                yield f'data: {chunk}\n\n'
            print(f'[DEBUG] Stream complete: {chunk_count} chunks')
        except Exception as e:
            print(f'[DEBUG] Error: {e}')
            yield f'data: Error: {str(e)}\n\n'
        yield 'data: [DONE]\n\n'
    
    return StreamingResponse(
        event_generator(),
        media_type='text/event-stream',
        headers={'Cache-Control': 'no-cache', 'Connection': 'keep-alive'},
    )
