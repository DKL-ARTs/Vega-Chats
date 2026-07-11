import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/chat_history.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _chats = [];

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    final chats = await ChatHistory.getChats();
    setState(() => _chats = chats);
  }

  Future<void> _deleteChat(int id) async {
    await ChatHistory.deleteChat(id);
    await _loadChats();
  }

  Future<void> _togglePinChat(int chatId) async {
    await ChatHistory.togglePinChat(chatId);
    await _loadChats();
  }

  Future<void> _renameChat(int chatId, String currentTitle) async {
    final textController = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: const Text('Переименовать чат', style: TextStyle(color: VegaTheme.textPrimary)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: VegaTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Введите название',
            hintStyle: TextStyle(color: VegaTheme.textSecondary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final newTitle = textController.text.trim();
              if (newTitle.isNotEmpty) {
                await ChatHistory.updateChatTitle(chatId, newTitle);
                await _loadChats();
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить', style: TextStyle(color: VegaTheme.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('History', style: TextStyle(color: VegaTheme.textPrimary)),
        backgroundColor: VegaTheme.dark,
        elevation: 0,
      ),
      body: _chats.isEmpty
          ? Center(child: Text('No chats yet', style: TextStyle(color: VegaTheme.textSecondary)))
          : ListView.builder(
              itemCount: _chats.length,
              itemBuilder: (ctx, i) {
                final chat = _chats[i];
                return ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -2),
                  contentPadding: const EdgeInsets.only(left: 16, right: 4),
                  title: Row(
                    children: [
                      if (chat['pinned'] == true) ...[
                        Icon(Icons.push_pin, color: VegaTheme.accent, size: 12),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          chat['title'] ?? 'Untitled',
                          style: TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: VegaTheme.textSecondary, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deleteChat(chat['id']);
                      } else if (value == 'pin') {
                        _togglePinChat(chat['id']);
                      } else if (value == 'rename') {
                        _renameChat(chat['id'], chat['title'] ?? 'Untitled');
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      final isPinned = chat['pinned'] == true;
                      return [
                        PopupMenuItem<String>(
                          value: 'pin',
                          child: Row(
                            children: [
                              Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: VegaTheme.accent, size: 18),
                              const SizedBox(width: 8),
                              Text(isPinned ? 'Открепить' : 'Закрепить', style: TextStyle(color: VegaTheme.textPrimary)),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, color: VegaTheme.textSecondary, size: 18),
                              const SizedBox(width: 8),
                              Text('Переименовать', style: TextStyle(color: VegaTheme.textPrimary)),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Text('Удалить', style: TextStyle(color: VegaTheme.textPrimary)),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                  onTap: () => context.push('/chat', extra: chat['id']),
                );
              },
            ),
    );
  }
}
