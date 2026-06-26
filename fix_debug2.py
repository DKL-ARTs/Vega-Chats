path = '/root/vega_chat/backend/app/providers/openrouter.py'
with open(path, 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'key_start' in line and 'OpenRouter' in line:
        new_line = '        print(f"[OpenRouter] has_referer={\'HTTP-Referer\' in dict(client.headers)}")' + '\n'
        lines.insert(i + 1, new_line)
        break

with open(path, 'w') as f:
    f.writelines(lines)
print('OK')
