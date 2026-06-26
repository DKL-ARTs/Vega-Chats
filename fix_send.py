import re

with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'r') as f:
    content = f.read()

# Find and replace the _send method
new_send = '''  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachedFile == null) || _loading) return;
    final fileToSend = _attachedFile;
    final fileNameToSend = _attachedFileName;
    final isImageToSend = _attachedIsImage;
    _controller.clear();
    FocusScope.of(context).unfocus();
    await _loadSettings();
    final msgContent = text;
    final displayText = text.isEmpty
        ? (isImageToSend ? '📷 Photo' : '📎 ' + (fileNameToSend ?? 'File'))
        : text;
    if (_currentChatId == null) {
      _currentChatId = await ChatHistory.createChat(displayText.length > 30 ? displayText.substring(0, 30) + '...' : displayText);
    }
    await ChatHistory.addMessage(
      _currentChatId!,
      'user',
      msgContent,
      filePath: fileToSend ?? '',
      fileName: fileNameToSend ?? '',
      isImage: isImageToSend,
    );
    await _loadChats();
    setState(() {
      _messages.add({'role': 'user', 'content': msgContent, 'filePath': fileToSend ?? '', 'fileName': fileNameToSend ?? '', 'isImage': isImageToSend});
      _attachedFile = null;
      _attachedFileName = null;
      _attachedIsImage = false;
      _loading = true;
    });
    _startThinking();
    try {
      List<Map<String, String>>? files;
      if (fileToSend != null) {
        final bytes = await File(fileToSend).readAsBytes();
        files = [{'name': fileNameToSend ?? 'file', 'content': base64Encode(bytes)}];
      }
      final messagesForBackend = _messages.map((m) => {
        'role': m['role'].toString(),
        'content': m['content'].toString(),
      }).toList();
      final resp = await _client.streamChat(messages: messagesForBackend, model: _model, files: files);
      _stopThinking();
      setState(() => _messages.add({'role': 'assistant', 'content': ''}));
      final respBody = await resp.body();
      if (_currentChatId != null) {
        await ChatHistory.addMessage(_currentChatId!, 'assistant', respBody);
      }
      if (mounted) setState(() { _messages.last['content'] = respBody; });
      await _loadChats();
    } catch (e) {
      _stopThinking();
      if (mounted) setState(() { _messages.add({'role': 'assistant', 'content': 'Error: '}); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }'''

# Use regex to find the _send method
pattern = r'  Future<void> _send\(\) async \{.*?\n  \}'
match = re.search(pattern, content, re.DOTALL)
if match:
    old = match.group()
    content = content.replace(old, new_send)
    with open('/root/vega_chat/mobile/lib/presentation/chat/chat_screen.dart', 'w') as f:
        f.write(content)
    print(f'OK - replaced {len(old)} chars')
else:
    print('NOT FOUND')
