path = '/root/vega_chat/backend/app/providers/openrouter.py'
with open(path, 'r') as f:
    content = f.read()

old = '''    def __init__(self, api_key: str = None):
        key = api_key or settings.openrouter_api_key
        self.client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers={
                'Authorization': f'Bearer {key}',
                'Content-Type': 'application/json',
            },
            timeout=120.0,
        )'''

new = '''    def __init__(self, api_key: str = None):
        key = api_key or settings.openrouter_api_key
        self.client = httpx.AsyncClient(
            base_url=settings.openrouter_base_url,
            headers={
                'Authorization': f'Bearer {key}',
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://vega-chat.app',
                'X-Title': 'Vega Chat',
            },
            timeout=120.0,
        )'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('OK')
else:
    print('NOT FOUND')
