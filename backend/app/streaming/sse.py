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
    if auth_header.startswith('Bearer '):
        raw_key = auth_header[7:]
        # Remove all whitespace and control chars
        cleaned = ''
        for ch in raw_key:
            if ch.isalnum() or ch in '-_.':
                cleaned += ch
        if len(cleaned) >= 20:
            api_key = cleaned
    elif 'api_key' in body:
        api_key = body['api_key']
    
    print(f'[DEBUG] model={model}, key_len={len(api_key) if api_key else 0}, auth_len={len(auth_header)}')
    
    # Add file content to messages for AI context
    if files:
        file_context = chr(10) + chr(10) + '[User attached files:]' + chr(10)
        for f in files:
            name = f.get('name', 'file')
            file_content = f.get('content', '')
            
            if name.lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                file_context += chr(10) + '- Image: ' + name + ' (attached for vision analysis)' + chr(10)
            else:
                try:
                    decoded = base64.b64decode(file_content).decode('utf-8', errors='ignore')
                    preview = decoded[:1500] + ('...' if len(decoded) > 1500 else '')
                    file_context += chr(10) + '--- File: ' + name + ' ---' + chr(10) + preview + chr(10) + '--- End ---' + chr(10)
                except:
                    file_context += chr(10) + '- File: ' + name + ' (binary)' + chr(10)
        
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                msg['content'] = msg.get('content', '') + file_context
                break
    
    # If image files attached, use vision format
    has_images = any(f.get('name', '').lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')) for f in files)
    if has_images and messages:
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                text_content = msg.get('content', '')
                images = []
                for f in files:
                    if f.get('name', '').lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                        images.append({
                            'type': 'image_url',
                            'image_url': {'url': 'data:image/jpeg;base64,' + f.get('content', '')}
                        })
                msg['content'] = [{'type': 'text', 'text': text_content}] + images
                break
    
    provider = get_provider(provider_name)
    
    async def event_generator():
        try:
            async for chunk in provider.stream(messages, model, api_key=api_key):
                yield 'data: ' + chunk + chr(10) + chr(10)
        except Exception as e:
            yield 'data: Error: ' + str(e) + chr(10) + chr(10)
        yield 'data: [DONE]' + chr(10) + chr(10)
    
    return StreamingResponse(
        event_generator(),
        media_type='text/event-stream',
        headers={'Cache-Control': 'no-cache', 'Connection': 'keep-alive'},
    )
