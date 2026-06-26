path = '/root/vega_chat/backend/app/providers/openrouter.py'
with open(path, 'r') as f:
    content = f.read()

old = "print(f'[OpenRouter] Using model: {model} key_len={len(key) if key else 0}')"

new = '''print(f'[OpenRouter] Using model: {model} key_len={len(key) if key else 0}')
        print(f'[OpenRouter] api_key_param={api_key is not None} settings_key_len={len(settings.openrouter_api_key) if settings.openrouter_api_key else 0}')
        print(f'[OpenRouter] key_start={repr(key[:8]) if key else None}')'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('OK')
else:
    print('NOT FOUND')
