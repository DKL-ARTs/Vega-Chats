with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'r') as f:
    lines = f.readlines()

new_lines = []
in_send_response = False

for i, line in enumerate(lines):
    if 'final resp = await _client.streamChat(' in line:
        in_send_response = True
        new_lines.append(line)
        new_lines.append('      _stopThinking();\n')
        new_lines.append('      setState(() => _messages.add({"role": "assistant", "content": ""}));\n')
        new_lines.append('      final respBody = resp.body;\n')
        new_lines.append('      if (_currentChatId != null) {\n')
        new_lines.append('        await ChatHistory.addMessage(_currentChatId!, "assistant", respBody);\n')
        new_lines.append('      }\n')
        new_lines.append('      if (mounted) setState(() { _messages.last["content"] = respBody; });\n')
        new_lines.append('      await _loadChats();\n')
        continue
    
    if in_send_response and 'await _loadChats();' in line:
        in_send_response = False
        continue
    
    if in_send_response:
        continue
    
    new_lines.append(line)

with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'w') as f:
    f.writelines(new_lines)
print('OK')
