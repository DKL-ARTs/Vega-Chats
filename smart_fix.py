import subprocess

# Read original file from git
result = subprocess.run(['git', 'show', 'HEAD:mobile/lib/presentation/chat/chat_screen.dart'], 
                       capture_output=True, text=True, cwd='/root/vega_chat')
content = result.stdout

# Find the _send method and replace the response handling
# We need to replace everything from 'final resp = await _client.streamChat' to 'await _loadChats()'

lines = content.split('\n')
new_lines = []
in_resp_section = False
brace_depth = 0

i = 0
while i < len(lines):
    line = lines[i]
    
    # Start of response handling
    if 'final resp = await _client.streamChat(' in line:
        in_resp_section = True
        new_lines.append(line)
        i += 1
        # Skip until we find 'await _loadChats()'
        while i < len(lines):
            if 'await _loadChats();' in lines[i]:
                # Add our clean response handling
                new_lines.append('      _stopThinking();')
                new_lines.append('      setState(() => _messages.add({"role": "assistant", "content": ""}));')
                new_lines.append('      final respBody = await resp.body();')
                new_lines.append('      if (_currentChatId != null) {')
                new_lines.append('        await ChatHistory.addMessage(_currentChatId!, "assistant", respBody);')
                new_lines.append('      }')
                new_lines.append('      if (mounted) setState(() { _messages.last["content"] = respBody; });')
                new_lines.append(lines[i])  # await _loadChats()
                in_resp_section = False
                i += 1
                break
            i += 1
        continue
    
    new_lines.append(line)
    i += 1

content = '\n'.join(new_lines)
with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'w') as f:
    f.write(content)
print('OK')
