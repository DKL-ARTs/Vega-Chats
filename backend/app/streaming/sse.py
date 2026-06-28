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
        api_key = auth_header[7:]
        print(f"[SSE] api_key={repr(api_key)}", file=sys.stderr)
    elif "api_key" in body and body["api_key"].strip():
        api_key = body["api_key"].strip()

    provider = get_provider(provider_name)

    if not api_key:
        return PlainTextResponse("Error: No API key", status_code=400)

    answer = await provider.chat(messages, model, api_key=api_key)
    return PlainTextResponse(answer)
