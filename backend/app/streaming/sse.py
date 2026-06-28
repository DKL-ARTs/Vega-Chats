import json
import sys
from fastapi import Request
from fastapi.responses import PlainTextResponse
from app.providers import get_provider
from fastapi import APIRouter

router = APIRouter()

@router.post("/chat/stream")
async def chat_stream(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    model = body.get("model", "openrouter/auto")
    provider_name = body.get("provider", "openrouter")

    api_key = None
    auth_header = request.headers.get("authorization", "")
    print(f"[SSE] auth_header={repr(auth_header)}", file=sys.stderr)
    if auth_header.startswith("Bearer "):
        raw_key = auth_header[7:]
        cleaned = "".join(ch for ch in raw_key if ch.isalnum() or ch in "-_.")
        print(f"[SSE] raw_key={repr(raw_key)} cleaned={repr(cleaned)}", file=sys.stderr)
        if len(cleaned) >= 20:
            api_key = cleaned
    elif "api_key" in body and body["api_key"].strip():
        api_key = body["api_key"].strip()

    provider = get_provider(provider_name)

    if not api_key:
        return PlainTextResponse("Error: No API key", status_code=400)

    answer = await provider.chat(messages, model, api_key=api_key)
    return PlainTextResponse(answer)
