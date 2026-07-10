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
                  title: Text(
                    chat['title'] ?? 'Untitled',
                    style: TextStyle(color: VegaTheme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(chat['createdAt']?.toString().substring(0, 10) ?? '', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
                  trailing: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: VegaTheme.textSecondary, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deleteChat(chat['id']);
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      return [
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: VegaTheme.textPrimary)),
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
