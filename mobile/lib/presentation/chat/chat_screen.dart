import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../data/database.dart';

class ChatScreen extends StatefulWidget {
  final int? chatId;
  const ChatScreen({super.key, this.chatId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <Map<String, String>>[];
  final _client = ApiClient();
  final _db = AppDatabase();
  bool _loading = false;
  bool _typing = false;
  String _model = 'openrouter/auto';
  int? _currentChatId;

  @override
  void initState() {
    super.initState();
    _currentChatId = widget.chatId;
    if (_currentChatId != null) {
      _loadChat(_currentChatId!);
    }
  }

  Future<void> _loadChat(int chatId) async {
    final messages = await _db.getMessages(chatId);
    setState(() {
      _messages.clear();
      for (final msg in messages) {
        _messages.add({'role': msg.role, 'content': msg.content});
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _controller.clear();
    FocusScope.of(context).unfocus();

    // Create chat if not exists
    if (_currentChatId == null) {
      _currentChatId = await _db.createChat(text.length > 30 ? text.substring(0, 30) + '...' : text);
    }

    // Save user message
    await _db.addMessage(_currentChatId!, 'user', text);

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _loading = true;
      _typing = true;
    });

    try {
      final resp = await _client.streamChat(messages: _messages, model: _model);
      final buffer = StringBuffer();
      setState(() => _messages.add({'role': 'assistant', 'content': ''}));
      
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ') && line != 'data: [DONE]') {
            final data = line.substring(6);
            buffer.write(data);
            setState(() {
              _messages.last['content'] = buffer.toString();
            });
          }
        }
      }

      // Save assistant message
      if (_currentChatId != null) {
        await _db.addMessage(_currentChatId!, 'assistant', buffer.toString());
      }
    } catch (e) {
      setState(() {
        _messages.add({'role': 'assistant', 'content': 'Error: $e'});
      });
    } finally {
      setState(() {
        _loading = false;
        _typing = false;
      });
    }
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied'),
        duration: Duration(seconds: 1),
        backgroundColor: VegaTheme.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('Vega Chat', style: TextStyle(color: VegaTheme.textPrimary)),
        actions: [
          IconButton(
            icon: Icon(Icons.history, color: VegaTheme.textSecondary),
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: Icon(Icons.terminal, color: VegaTheme.textSecondary),
            onPressed: () => context.push('/terminal'),
          ),
          IconButton(
            icon: Icon(Icons.folder_outlined, color: VegaTheme.textSecondary),
            onPressed: () => context.push('/ide'),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: VegaTheme.textSecondary),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (_typing && i == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: VegaTheme.assistantBubble,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VegaTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(VegaTheme.accent),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Thinking...', style: TextStyle(color: VegaTheme.textSecondary)),
                        ],
                      ),
                    ),
                  );
                }
                final msg = _messages[i];
                final isUser = msg['role'] == 'user';
                return GestureDetector(
                  onLongPress: () => _copyMessage(msg['content'] ?? ''),
                  child: Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(ctx).size.width * 0.8,
                      ),
                      decoration: BoxDecoration(
                        color: isUser ? VegaTheme.userBubble : VegaTheme.assistantBubble,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VegaTheme.border),
                      ),
                      child: Text(
                        msg['content'] ?? '',
                        style: TextStyle(color: VegaTheme.textPrimary, fontSize: 15),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: VegaTheme.dark,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: VegaTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: TextStyle(color: VegaTheme.textSecondary),
                      filled: true,
                      fillColor: VegaTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loading ? null : _send,
                  icon: Icon(Icons.send, color: VegaTheme.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _db.close();
    super.dispose();
  }
}
