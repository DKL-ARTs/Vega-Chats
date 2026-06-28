import json
import re
import sys
import base64
from fastapi import Request
from fastapi.responses import PlainTextResponse
from app.providers import get_provider
from fastapi import APIRouter

router = APIRouter()

def parse_message_content(content):
    """Convert markdown image syntax to OpenRouter image_url format and extract file references"""
    pattern = r'!\[image\]\(data:([^)]+)\)'
    matches = re.findall(pattern, content)
    
    if not matches:
        return content, [], []
    
    text = re.sub(pattern, '', content).strip()
    images = []
    for data_uri in matches:
        images.append({
            "type": "image_url",
            "image_url": {"url": f"data:{data_uri}"}
        })
    
    return text, images, []

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
        return PlainTextResponse("Error: No API key", status_code=400)

    # Reconstruct proper key if dashes were stripped
    if api_key and not api_key.startswith("sk-or-"):
        if api_key.startswith("skorv1"):
            api_key = "sk-or-v1-" + api_key[6:]
    
    # Process files - insert text file content into messages
    for file_data in files:
        file_name = file_data.get("name", "file")
        file_content_b64 = file_data.get("content", "")
        
        # Try to decode as text
        try:
            file_text = base64.b64decode(file_content_b64).decode("utf-8")
            file_msg = {
                "role": "user",
                "content": f"\n\n--- File: {file_name} ---\n{file_text}\n--- End of {file_name} ---"
            }
            messages.append(file_msg)
        except UnicodeDecodeError:
            # Binary file - skip for now
            file_msg = {
                "role": "user",
                "content": f"\n\n[Binary file: {file_name} - cannot display]"
            }
            messages.append(file_msg)

    # Process messages - convert images to proper format
    processed_messages = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        
        text, images = parse_message_content(content)
        
        if images:
            msg_content = []
            if text:
                msg_content.append({"type": "text", "text": text})
            msg_content.extend(images)
            processed_messages.append({"role": role, "content": msg_content})
        else:
            processed_messages.append({"role": role, "content": content})

    print(f"[SSE] messages_count={len(processed_messages)} file_msgs_added={len(files)}", file=sys.stderr)
    answer = await provider.chat(processed_messages, model, api_key=api_key)
    return PlainTextResponse(answer)
