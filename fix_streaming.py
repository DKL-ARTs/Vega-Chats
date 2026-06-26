path = '/root/vega_chat/backend/app/providers/openrouter.py'
with open(path, 'r') as f:
    content = f.read()

# Replace the stream call with a non-stream call wrapped in async generator
old = '''            async with self.client.stream('POST', '/chat/completions', json={
                'model': model,
                'messages': messages,
                'stream': True,
                **kwargs,
            }) as resp:
                if resp.status_code != 200:
                    error_text = await resp.aread()
                    yield f'Error: HTTP {resp.status_code}'
                    return'''

new = '''            or_resp = await self.client.post('/chat/completions', json={
                'model': model,
                'messages': messages,
                'stream': True,
                **kwargs,
            })
            if or_resp.status_code != 200:
                yield f'Error: HTTP {or_resp.status_code}: {or_resp.text[:200]}'
                return
            async for line in or_resp.aiter_lines():
                yield line'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('OK')
else:
    print('NOT FOUND')
