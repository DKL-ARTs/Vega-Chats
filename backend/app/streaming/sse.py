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
    
    # Get API key from Authorization header, body, or env
    api_key = None
    auth_header = request.headers.get('authorization', '')
    if auth_header.startswith('Bearer '):
        raw_key = auth_header[7:]
        # Remove all whitespace and control chars
        cleaned = raw_key.strip().replace(' ', '').replace('	', '').replace('', '').replace('
', '')
        api_key = cleaned if len(cleaned) >= 20 else None
    elif 'api_key' in body:
        api_key = body['api_key']
    
    # No fallback - key must come from client
    
    print(f'[DEBUG] model={model}, msg_count={len(messages)}, files={len(files)}, key_len={len(api_key) if api_key else 0}, auth_header_len={len(auth_header)}')
    
    # Add file content to messages for AI context
    if files:
        file_context = '\n\n[User attached files:]\n'
        for f in files:
            name = f.get('name', 'file')
            content = f.get('content', '')
            
            if name.lower().endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                file_context += f'\n- Image: {name} (attached for vision analysis)\n'
            else:
                try:
                    decoded = base64.b64decode(content).decode('utf-8', errors='ignore')
                    preview = decoded[:1500] + ('...' if len(decoded) > 1500 else '')
                    file_context += f'\n--- File: {name} ---\n{preview}\n--- End ---\n'
                except:
                    file_context += f'\n- File: {name} (binary)\n'
        
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                msg['content'] = msg.get('content', '') + file_context
                break
    
    # If image files attached, use vision format for supported models
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
                            'image_url': {'url': f'data:image/jpeg;base64,{f.get(content, )}'}
                        })
                msg['content'] = [{'type': 'text', 'text': text_content}] + images
                break
    
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
