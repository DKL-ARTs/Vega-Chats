with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'r') as f:
    content = f.read()

# 1. Replace 'await for (final chunk in resp.stream.transform(utf8.decoder)) {' with 'final respBody = await resp.body();'
content = content.replace(
    'await for (final chunk in resp.stream.transform(utf8.decoder)) {',
    'final respBody = await resp.body();'
)

# 2. Remove SSE parsing lines
for pattern in [
    'sseBuf += chunk;',
    'while (true) {',
    'final sepIdx = sseBuf.indexOf',
    'if (sepIdx == -1) break;',
    'final event = sseBuf.substring(0, sepIdx);',
    'sseBuf = sseBuf.substring(sepIdx + 2);',
    'for (final line in event.split',
    'if (line.startsWith(\'data: \'))',
    'final data = line.substring(6);',
    'if (data == \'[DONE]\') continue;',
    'buffer.write(data);',
    'if (mounted) setState(() { _messages.last[\'content\'] = buffer.toString(); });',
    'sseBuf = \'\'];',
    'final buffer = StringBuffer();',
    'String sseBuf = \'\';',
]:
    content = content.replace(pattern + '\n', '')

# 3. Replace 'await ChatHistory.addMessage(_currentChatId!, \'assistant\', currentMessage);'
# with reading respBody
content = content.replace(
    'await ChatHistory.addMessage(_currentChatId!, \'assistant\', currentMessage);',
    'await ChatHistory.addMessage(_currentChatId!, \'assistant\', respBody);'
)

# 4. Replace 'final currentMessage = buffer.toString();' with 'final currentMessage = respBody;'
content = content.replace(
    'final currentMessage = buffer.toString();',
    'final currentMessage = respBody;'
)

# 5. Add setState to show response
content = content.replace(
    'await _loadChats();\n    } catch',
    'if (mounted) setState(() { _messages.last[\'content\'] = respBody; });\n      await _loadChats();\n    } catch'
)

with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'w') as f:
    f.write(content)

print('OK')
