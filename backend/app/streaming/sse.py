import json
import re
import sys
from fastapi import Request
from fastapi.responses import StreamingResponse
from app.providers import get_provider
from fastapi import APIRouter

router = APIRouter()

def parse_message_content(content):
    """Extract images from markdown, return clean text and image objects"""
    pattern = r'!\[image\]\(data:([^)]+)\)'
    matches = re.findall(pattern, content)
    
    if not matches:
        return content, []
    
    clean_text = re.sub(pattern, '[Изображение]', content).strip()
    
    images = []
    for data_uri in matches:
        images.append({
            "type": "image_url",
            "image_url": {"url": f"data:{data_uri}"}
        })
    
    return clean_text, images

@router.post("/chat/stream")
async def chat_stream(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    files = body.get("files", [])
    model = body.get("model", "openrouter/auto")
    provider_name = body.get("provider", "openrouter")

    api_key = None
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        api_key = auth_header[7:]
    elif "api_key" in body and body["api_key"].strip():
        api_key = body["api_key"].strip()

    if not api_key:
        api_key = request.headers.get("x-api-key", "")

    provider = get_provider(provider_name)

    if not api_key:
        yield f"data: Error: No API key\n\n"
        return

    # Reconstruct proper key format
    if api_key and not api_key.startswith("sk-or-"):
        if api_key.startswith("skorv1"):
            api_key = "sk-or-v1-" + api_key[6:]
    
    # Add system message for text-only responses
    system_msg = {
        "role": "system",
        "content": "Ты полезный ассистент. Когда пользователь отправляет изображение, опиши что на нём видишь текстом. Не используй JSON, координаты или структурированные форматы. Отвечай простым текстом на русском языке."
    }
    
    # Process files (text files only)
    for file_data in files:
        file_name = file_data.get("name", "file")
        file_content_b64 = file_data.get("content", "")
        try:
            import base64
            file_text = base64.b64decode(file_content_b64).decode("utf-8")
            messages.append({
                "role": "user",
                "content": f"\n\n--- Файл: {file_name} ---\n{file_text}\n--- Конец файла ---"
            })
        except:
            pass

    # Process messages - convert images to OpenRouter format
    processed_messages = [system_msg]
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        
        clean_text, images = parse_message_content(content)
        
        if images:
            msg_content = []
            if clean_text and clean_text != '[Изображение]':
                msg_content.append({"type": "text", "text": clean_text})
            else:
                msg_content.append({"type": "text", "text": ""})
            msg_content.extend(images)
            processed_messages.append({"role": role, "content": msg_content})
        else:
            processed_messages.append({"role": role, "content": content})

    async def generate():
        try:
            async for chunk in provider.stream(processed_messages, model, api_key=api_key):
                if chunk.startswith("data: "):
                    json_str = chunk[6:].strip()
                    if json_str and json_str != "[DONE]":
                        try:
                            data = json.loads(json_str)
                            choices = data.get("choices", [])
                            if choices:
                                delta = choices[0].get("delta", {})
                                content = delta.get("content", "")
                                if content:
                                    yield f"data: {json.dumps({'content': content}, ensure_ascii=False)}\n\n"
                        except json.JSONDecodeError:
                            pass
                elif not chunk.startswith("Error:"):
                    yield f"data: {json.dumps({'content': chunk}, ensure_ascii=False)}\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: Error: {str(e)}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")
