import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <Map<String, String>>[];
  final _client = ApiClient();
  bool _loading = false;
  String _model = 'openrouter/auto';

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _controller.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _loading = true;
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
    } catch (e) {
      setState(() {
        _messages.add({'role': 'assistant', 'content': 'Error: $e'});
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('Vega Chat', style: TextStyle(color: VegaTheme.textPrimary)),
        actions: [
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
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final msg = _messages[i];
                final isUser = msg['role'] == 'user';
                return Align(
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
                );
              },
            ),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                backgroundColor: VegaTheme.border,
                valueColor: AlwaysStoppedAnimation(VegaTheme.accent),
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
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
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
    super.dispose();
  }
}
