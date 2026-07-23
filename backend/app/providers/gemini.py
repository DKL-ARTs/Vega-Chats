import httpx
from app.config import settings

GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai"

# Remap stale/removed model IDs to current equivalents
GEMINI_MODEL_REMAP = {
    "gemini-2.5-flash": "gemini-3.6-flash",
    "gemini-2.5-pro": "gemini-3.1-pro-preview",
    "gemini-2.0-flash": "gemini-3.6-flash",
    "gemini-2.5-flash-lite": "gemini-3.5-flash-lite",
    "gemini-1.5-flash": "gemini-3.6-flash",
}

DEFAULT_GEMINI_MODEL = "gemini-3.6-flash"


def _resolve_gemini_model(model: str) -> str:
    """Remap removed/stale model names to current ones."""
    return GEMINI_MODEL_REMAP.get(model, model) if model else DEFAULT_GEMINI_MODEL


class GeminiProvider:
    name = "gemini"

    def __init__(self, api_key: str = None):
        self.api_key = api_key or settings.gemini_api_key

    async def chat(self, messages: list[dict], model: str = None, **kwargs) -> str:
        model = _resolve_gemini_model(model)
        key = kwargs.get("api_key") or self.api_key
        if not key or not key.strip():
            return "Error: No Gemini API key provided"
        async with httpx.AsyncClient(base_url=GEMINI_BASE_URL, timeout=120.0) as client:
            resp = await client.post("/chat/completions", json={
                "model": model,
                "messages": messages,
            }, headers={
                "Authorization": f"Bearer {key.strip()}",
                "Content-Type": "application/json",
            })
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"]

    async def stream(self, messages: list[dict], model: str = None, api_key: str = None, **kwargs):
        model = _resolve_gemini_model(model)
        key = api_key or self.api_key
        if not key or not key.strip():
            yield "Error: No Gemini API key provided"
            return

        # Remove unsupported kwargs (e.g. tools) — Gemini via OpenAI compat supports tools
        # but we pass them through only if present
        body = {
            "model": model,
            "messages": messages,
            "stream": True,
        }
        if kwargs.get("tools"):
            body["tools"] = kwargs["tools"]

        try:
            async with httpx.AsyncClient(base_url=GEMINI_BASE_URL, timeout=120.0) as client:
                async with client.stream("POST", "/chat/completions", json=body, headers={
                    "Authorization": f"Bearer {key.strip()}",
                    "Content-Type": "application/json",
                }) as resp:
                    if resp.status_code != 200:
                        error_text = await resp.aread()
                        yield f"Error: HTTP {resp.status_code}: {error_text[:300]}"
                        return
                    async for line in resp.aiter_lines():
                        if line:
                            yield line
        except Exception as e:
            yield f"Error: {str(e)}"
