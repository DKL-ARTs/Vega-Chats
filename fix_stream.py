path = '/root/vega_chat/backend/app/providers/openrouter.py'
with open(path, 'r') as f:
    content = f.read()

old = '''    async def stream(self, messages: list[dict], model: str = None, api_key: str = None, **kwargs):
        model = model or settings.default_model
        key = api_key or settings.openrouter_api_key
        client = self.client
        if api_key and api_key != settings.openrouter_api_key:
            client = httpx.AsyncClient(
                base_url=settings.openrouter_base_url,
                headers={
                    'Authorization': 'Bearer ' + key,
                    'Content-Type': 'application/json',
                    'HTTP-Referer': 'https://vega-chat.app',
                    'X-Title': 'Vega Chat',
                },
                timeout=120.0,
            )
        print(f'[OpenRouter] Using model: {model} key_len={len(key) if key else 0}')
        print(f'[OpenRouter] api_key_param={api_key is not None} settings_key_len={len(settings.openrouter_api_key) if settings.openrouter_api_key else 0}')
        print(f'[OpenRouter] key_start={repr(key[:8]) if key else None}')'''

new = '''    async def stream(self, messages: list[dict], model: str = None, api_key: str = None, **kwargs):
        model = model or settings.default_model
        key = api_key or settings.openrouter_api_key
        # Always create fresh client with proper headers
        client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers={
                'Authorization': 'Bearer ' + key,
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://vega-chat.app',
                'X-Title': 'Vega Chat',
            },
            timeout=120.0,
        )
        print(f'[OpenRouter] Using model: {model} key_len={len(key) if key else 0}')
        print(f'[OpenRouter] api_key_param={api_key is not None} settings_key_len={len(settings.openrouter_api_key) if settings.openrouter_api_key else 0}')
        print(f'[OpenRouter] key_start={repr(key[:8]) if key else None}')'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('OK')
else:
    print('NOT FOUND')
