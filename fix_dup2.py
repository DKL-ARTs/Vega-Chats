path = '/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart'
with open(path, 'r') as f:
    lines = f.readlines()

# Remove duplicate addMessage lines
new_lines = []
skip = False
for i, line in enumerate(lines):
    if skip:
        skip = False
        continue
    if 'addMessage' in line and 'resp.body' in line:
        new_lines.append(line)
        # Skip the next line if it's also an addMessage
        if i + 1 < len(lines) and 'addMessage' in lines[i + 1]:
            skip = True
    else:
        new_lines.append(line)

with open(path, 'w') as f:
    f.writelines(new_lines)
print('OK')
