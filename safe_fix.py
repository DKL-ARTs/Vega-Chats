with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'r') as f:
    lines = f.readlines()

# Find line numbers
start_line = None  # 'final resp = await _client.streamChat('
end_line = None    # 'await _loadChats();' inside try block

for i, line in enumerate(lines):
    if 'final resp = await _client.streamChat(' in line:
        start_line = i
    if start_line is not None and 'await _loadChats();' in line and i > start_line:
        end_line = i
        break

print(f'Found: start={start_line}, end={end_line}')

if start_line is not None and end_line is not None:
    new_lines = lines[:start_line]  # Everything before
    new_lines.append('      final resp = await _client.streamChat(messages: messagesForBackend, model: _model, files: files);\n')
    new_lines.append('      _stopThinking();\n')
    new_lines.append('      setState(() => _messages.add({"role": "assistant", "content": ""}));\n')
    new_lines.append('      final respBody = resp.body;\n')
    new_lines.append('      if (_currentChatId != null) {\n')
    new_lines.append('        await ChatHistory.addMessage(_currentChatId!, "assistant", respBody);\n')
    new_lines.append('      }\n')
    new_lines.append('      if (mounted) setState(() { _messages.last["content"] = respBody; });\n')
    new_lines.append(lines[end_line])  # await _loadChats();
    new_lines.extend(lines[end_line+1:])  # Everything after
    
    with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'w') as f:
        f.writelines(new_lines)
    print('OK')
else:
    print('NOT FOUND')
