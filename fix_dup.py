path = '/root/vega_chat/backend/app/providers/openrouter.py'
with open(path, 'r') as f:
    lines = f.readlines()

# Remove duplicate lines 51 and 52 (0-indexed: 50, 51)
# Line 50 (idx 49) is the correct one
new_lines = []
skip_next = 0
for i, line in enumerate(lines):
    if skip_next > 0:
        skip_next -= 1
        continue
    new_lines.append(line)
    # After we add the correct has_referer line, skip the next 2 duplicates
    if 'has_referer' in line and 'HTTP-Referer' in line and 'chr' not in line:
        skip_next = 2

with open(path, 'w') as f:
    f.writelines(new_lines)
print('OK')
