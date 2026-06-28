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
    if auth_header.startswith("Bearer "):
        api_key = auth_header[7:]
    elif "api_key" in body and body["api_key"].strip():
        api_key = body["api_key"].strip()

    # Also try to get key from query param or header directly
    if not api_key:
        api_key = request.headers.get("x-api-key", "")

    provider = get_provider(provider_name)

    if not api_key:
        return PlainTextResponse("Error: No API key", status_code=400)

    # Reconstruct proper key if dashes were stripped
    # OpenRouter keys: sk-or-v1-XXXX-XXXX-XXXX
    if api_key and not api_key.startswith("sk-or-"):
        # Try inserting dashes: sk + or + v1 + hash
        if api_key.startswith("skorv1"):
            api_key = "sk-or-v1-" + api_key[6:]

    print(f"[SSE] final_api_key={repr(api_key)}", file=sys.stderr)
    answer = await provider.chat(messages, model, api_key=api_key)
    return PlainTextResponse(answer)
