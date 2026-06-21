import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../data/chat_history.dart';

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
  bool _loading = false;
  bool _typing = false;
  String _model = 'openrouter/auto';
  int? _currentChatId;
  List<Map<String, dynamic>> _chats = [];

  @override
  void initState() {
    super.initState();
    _currentChatId = widget.chatId;
    _loadChats();
    if (_currentChatId != null) {
      _loadChat(_currentChatId!);
    }
  }

  Future<void> _loadChats() async {
    final chats = await ChatHistory.getChats();
    setState(() => _chats = chats);
  }

  Future<void> _loadChat(int chatId) async {
    final messages = await ChatHistory.getMessages(chatId);
    setState(() {
      _messages.clear();
      for (final msg in messages) {
        _messages.add({'role': msg['role'], 'content': msg['content']});
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    if (_currentChatId == null) {
      _currentChatId = await ChatHistory.createChat(
        text.length > 30 ? text.substring(0, 30) + '...' : text
      );
    }
    await ChatHistory.addMessage(_currentChatId!, 'user', text);
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
            setState(() { _messages.last['content'] = buffer.toString(); });
          }
        }
      }
      if (_currentChatId != null) {
        await ChatHistory.addMessage(_currentChatId!, 'assistant', buffer.toString());
      }
      await _loadChats();
    } catch (e) {
      setState(() { _messages.add({'role': 'assistant', 'content': 'Error: $e'}); });
    } finally {
      setState(() { _loading = false; _typing = false; });
    }
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied'), duration: Duration(seconds: 1), backgroundColor: VegaTheme.surface));
  }

  void _startNewChat() {
    Navigator.pop(context);
    setState(() {
      _currentChatId = null;
      _messages.clear();
      _loading = false;
      _typing = false;
    });
  }

  void _openChat(int chatId) {
    Navigator.pop(context);
    setState(() {
      _currentChatId = chatId;
    });
    _loadChat(chatId);
  }

  bool get _isNewChat => _currentChatId == null && _messages.isEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.75,
        backgroundColor: VegaTheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Chats', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: Icon(Icons.add, color: VegaTheme.accent),
                      onPressed: _startNewChat,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _chats.isEmpty
                    ? Center(child: Text('No chats yet', style: TextStyle(color: VegaTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: _chats.length,
                        itemBuilder: (ctx, i) {
                          final chat = _chats[i];
                          final isActive = chat['id'] == _currentChatId;
                          return ListTile(
                            selected: isActive,
                            selectedTileColor: VegaTheme.card,
                            leading: Icon(Icons.chat_bubble_outline, color: isActive ? VegaTheme.accent : VegaTheme.textSecondary),
                            title: Text(chat['title'] ?? 'Untitled', style: TextStyle(color: isActive ? VegaTheme.accent : VegaTheme.textPrimary)),
                            subtitle: Text(chat['createdAt']?.toString().substring(0, 10) ?? '', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: VegaTheme.textSecondary, size: 20),
                              onPressed: () async {
                                await ChatHistory.deleteChat(chat['id']);
                                await _loadChats();
                              },
                            ),
                            onTap: () => _openChat(chat['id']),
                          );
                        },
                      ),
              ),
              Divider(color: VegaTheme.border),
              ListTile(
                leading: Icon(Icons.folder_outlined, color: VegaTheme.accent),
                title: Text('Files', style: TextStyle(color: VegaTheme.textPrimary)),
                onTap: () { Navigator.pop(context); context.push('/ide'); },
              ),
              ListTile(
                leading: Icon(Icons.terminal, color: VegaTheme.accent),
                title: Text('Terminal', style: TextStyle(color: VegaTheme.textPrimary)),
                onTap: () { Navigator.pop(context); context.push('/terminal'); },
              ),
              ListTile(
                leading: Icon(Icons.settings_outlined, color: VegaTheme.accent),
                title: Text('Settings', style: TextStyle(color: VegaTheme.textPrimary)),
                onTap: () { Navigator.pop(context); context.push('/settings'); },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: VegaTheme.textSecondary),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          if (!_isNewChat)
            IconButton(
              icon: Icon(Icons.add, color: VegaTheme.textSecondary),
              onPressed: _startNewChat,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && !_typing
                ? Center(child: Text('Start a conversation', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 16)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_typing ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_typing && i == _messages.length) {
                        return Align(alignment: Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: VegaTheme.assistantBubble, borderRadius: BorderRadius.circular(12), border: Border.all(color: VegaTheme.border)), child: Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(VegaTheme.accent))), const SizedBox(width: 8), Text('Thinking...', style: TextStyle(color: VegaTheme.textSecondary))])));
                      }
                      final msg = _messages[i];
                      final isUser = msg['role'] == 'user';
                      return GestureDetector(
                        onLongPress: () => _copyMessage(msg['content'] ?? ''),
                        child: Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.8), decoration: BoxDecoration(color: isUser ? VegaTheme.userBubble : VegaTheme.assistantBubble, borderRadius: BorderRadius.circular(12), border: Border.all(color: VegaTheme.border)), child: Text(msg['content'] ?? '', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 15)))),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: VegaTheme.dark,
            child: Row(children: [
              Expanded(child: TextField(controller: _controller, style: TextStyle(color: VegaTheme.textPrimary), decoration: InputDecoration(hintText: 'Message...', hintStyle: TextStyle(color: VegaTheme.textSecondary), filled: true, fillColor: VegaTheme.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)), onSubmitted: (_) => _send())),
              const SizedBox(width: 8),
              IconButton(onPressed: _loading ? null : _send, icon: Icon(Icons.send, color: VegaTheme.accent)),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}
