import json
import re
import sys
import logging
from fastapi import Request
from fastapi.responses import StreamingResponse
from app.providers import get_provider
from fastapi import APIRouter

router = APIRouter()
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", stream=sys.stdout)
log = logging.getLogger("sse")

# Startup marker - will appear in Railway logs on import
print("=" * 50, flush=True)
print("[SSE] sse.py loaded - version with debug logging 2d3e8f80", flush=True)
print("=" * 50, flush=True)


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
    # Log immediately on entry (before anything else)
    print("[SSE] >>> chat_stream called", flush=True)
    body = await request.json()
    messages = body.get("messages", [])
    files = body.get("files", [])
    model = body.get("model", "openrouter/auto")
    provider_name = body.get("provider", "openrouter")
    print("[SSE] >>> parsed body: msgs=" + str(len(messages)) + ", model=" + str(model), flush=True)

    api_key = None
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        api_key = auth_header[7:]
    elif "api_key" in body and body["api_key"].strip():
        api_key = body["api_key"].strip()

    if not api_key:
        api_key = request.headers.get("x-api-key", "")

    # Fallback to environment variable
    if not api_key:
        from app.config import settings
        api_key = settings.openrouter_api_key

    # DEBUG: Log what we received (use stderr + logging to ensure Railway captures it)
    masked = api_key[:10] + "..." + api_key[-4:] if len(api_key) > 14 else api_key
    body_key = body.get("api_key", "")
    has_body = bool(body_key.strip())
    log_msg = "[SSE] api_key: len=" + str(len(api_key)) + ", preview=" + masked + ", has_auth=" + str(bool(auth_header)) + ", has_body=" + str(has_body) + ", msgs=" + str(len(messages)) + ", model=" + str(model)
    sys.stderr.write(log_msg + "\n")
    sys.stderr.flush()
    log.info(log_msg)

    provider = get_provider(provider_name)

    if not api_key:
        err_msg = "[SSE] ERROR: No API key provided!"
        sys.stderr.write(err_msg + "\n")
        sys.stderr.flush()
        log.error(err_msg)
        async def no_key():
            yield "data: Error: No API key\n\n"
        return StreamingResponse(no_key(), media_type="text/event-stream")

    # Reconstruct proper key format
    if api_key and not api_key.startswith("sk-or-"):
        if api_key.startswith("skorv1"):
            api_key = "sk-or-v1-" + api_key[6:]

    # Add system message for text-only responses
    system_msg = {
        "role": "system",
        "content": (
            "Ты полезный ассистент. Отвечай на русском языке.\n"
            "ФОРМАТИРОВАНИЕ: Используй богатый Markdown для структурированных ответов:\n"
            "- Заголовки: ## для разделов, ### для подразделов\n"
            "- **Жирный** для ключевых терминов и важных слов\n"
            "- Нумерованные и маркированные списки для перечислений\n"
            "- `код` для inline-кода, ```блоки``` для многострочного кода\n"
            "- > цитаты для выделения важного\n"
            "- --- горизонтальные разделители между крупными секциями\n"
            "- Таблицы когда нужно сравнение\n"
            "Когда пользователь отправляет изображение, опиши что на нём видишь текстом. "
            "Не используй JSON, координаты или структурированные форматы."
        )
    }

    # Process files (text files only)
    import base64
    for file_data in files:
        file_name = file_data.get("name", "file")
        file_content_b64 = file_data.get("content", "")
        try:
            file_text = base64.b64decode(file_content_b64).decode("utf-8")
            messages.append({
                "role": "user",
                "content": f"\n\n--- Файл: {file_name} ---\n{file_text}\n--- Конец файла ---"
            })
        except Exception:
            pass

    # Process messages - convert images to OpenRouter format
    processed_messages = [system_msg]
    for msg in messages:
        role = msg.get("role", "user")
        msg_content_str = msg.get("content", "")

        clean_text, images = parse_message_content(msg_content_str)

        if images:
            msg_content = []
            if clean_text and clean_text != '[Изображение]':
                msg_content.append({"type": "text", "text": clean_text})
            else:
                msg_content.append({"type": "text", "text": ""})
            msg_content.extend(images)
            processed_messages.append({"role": role, "content": msg_content})
        else:
            processed_messages.append({"role": role, "content": msg_content_str})

    async def generate():
        try:
            async for raw_chunk in provider.stream(processed_messages, model, api_key=api_key):
                # Handle multi-line chunks (provider may yield multiple lines at once)
                lines = raw_chunk.split("\n")
                for chunk in lines:
                    chunk = chunk.strip()
                    if not chunk:
                        continue
                    if chunk.startswith("data: "):
                        json_str = chunk[6:].strip()
                        if not json_str or json_str == "[DONE]":
                            continue
                        try:
                            data = json.loads(json_str)
                            choices = data.get("choices", [])
                            if choices:
                                delta = choices[0].get("delta", {})
                                delta_content = delta.get("content", "")
                                if delta_content:
                                    yield "data: " + json.dumps({"content": delta_content}, ensure_ascii=False) + "\n\n"
                        except Exception:
                            pass
                    elif not chunk.startswith("Error:") and not chunk.startswith(":"):
                        yield "data: " + json.dumps({"content": chunk}, ensure_ascii=False) + "\n\n"
            yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: Error: {str(e)}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")
