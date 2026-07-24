import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/theme.dart';
import '../../data/chat_history.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoriteEntry {
  final int chatId;
  final String chatTitle;
  final int msgIndex;
  final Map<String, dynamic> message;

  _FavoriteEntry({
    required this.chatId,
    required this.chatTitle,
    required this.msgIndex,
    required this.message,
  });
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  List<_FavoriteEntry> _entries = [];
  bool _loading = true;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _loadFavorites();
  }

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _shimmerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final chats = await ChatHistory.getChats();
    final entries = <_FavoriteEntry>[];
    for (final chat in chats) {
      final chatId = chat['id'] as int?;
      if (chatId == null) continue;
      final title = (chat['title'] as String?) ?? 'Чат';
      final messages = ((chat['messages'] as List?) ?? [])
          .cast<Map<String, dynamic>>();
      for (int i = 0; i < messages.length; i++) {
        final msg = messages[i];
        if (msg['isFavorite'] == true) {
          entries.add(_FavoriteEntry(
            chatId: chatId,
            chatTitle: title,
            msgIndex: i,
            message: msg,
          ));
        }
      }
    }

    // Sort chronologically (oldest chat/message first, newest last)
    entries.sort((a, b) {
      final chatCmp = a.chatId.compareTo(b.chatId);
      if (chatCmp != 0) return chatCmp;
      return a.msgIndex.compareTo(b.msgIndex);
    });

    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _unfavorite(_FavoriteEntry entry) async {
    final chats = await ChatHistory.getChats();
    for (final chat in chats) {
      if (chat['id'] == entry.chatId) {
        final messages = ((chat['messages'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        if (entry.msgIndex < messages.length) {
          messages[entry.msgIndex]['isFavorite'] = false;
          await ChatHistory.overwriteMessages(entry.chatId, messages);
        }
        break;
      }
    }
    await _loadFavorites();
  }

  void _copyContent(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Скопировано', style: TextStyle(color: Colors.white)),
        backgroundColor: VegaTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildShimmer() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (_, __) {
        final gradient = LinearGradient(
          colors: [
            VegaTheme.surface,
            VegaTheme.card,
            VegaTheme.surface,
          ],
          stops: [
            (_shimmerController.value - 0.3).clamp(0.0, 1.0),
            _shimmerController.value.clamp(0.0, 1.0),
            (_shimmerController.value + 0.3).clamp(0.0, 1.0),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF7C4DFF), Color(0xFFAA80FF)],
            ).createShader(bounds),
            child: const Icon(
              Icons.star_rounded,
              size: 72,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет избранных',
            style: TextStyle(
              color: VegaTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Нажми ★ под ответом нейронки\nчтобы сохранить его сюда',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: VegaTheme.textSecondary,
              fontSize: 15,
              height: 1.5,
            ),
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
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)],
              ).createShader(b),
              child: const Icon(Icons.star_rounded, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text(
              'Избранное',
              style: TextStyle(
                color: VegaTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (!_loading && _entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: VegaTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_entries.length}',
                    style: const TextStyle(
                      color: VegaTheme.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: VegaTheme.border.withOpacity(0.4),
          ),
        ),
      ),
      body: _loading
          ? _buildShimmer()
          : _entries.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: VegaTheme.accent,
                  backgroundColor: VegaTheme.surface,
                  onRefresh: _loadFavorites,
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _FavoriteCardItem(
                      key: ValueKey('${_entries[i].chatId}_${_entries[i].msgIndex}'),
                      entry: _entries[i],
                      onUnfavorite: () => _unfavorite(_entries[i]),
                      onCopy: _copyContent,
                    ),
                  ),
                ),
    );
  }
}

class _FavoriteCardItem extends StatefulWidget {
  final _FavoriteEntry entry;
  final VoidCallback onUnfavorite;
  final Function(String) onCopy;

  const _FavoriteCardItem({
    required this.entry,
    required this.onUnfavorite,
    required this.onCopy,
    super.key,
  });

  @override
  State<_FavoriteCardItem> createState() => _FavoriteCardItemState();
}

class _FavoriteCardItemState extends State<_FavoriteCardItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final msg = entry.message;
    final content = (msg['content'] as String?) ?? '';
    final isUser = msg['role'] == 'user';
    final isLong = content.length > 250 || content.split('\n').length > 5;

    return Dismissible(
      key: ValueKey('${entry.chatId}_${entry.msgIndex}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.star_border_rounded, color: Colors.red, size: 28),
      ),
      onDismissed: (_) => widget.onUnfavorite(),
      child: Container(
        decoration: BoxDecoration(
          color: VegaTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: VegaTheme.accent.withOpacity(0.18),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)],
                    ).createShader(b),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.chatTitle,
                      style: const TextStyle(
                        color: VegaTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Role chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isUser
                          ? VegaTheme.accentBlue.withOpacity(0.15)
                          : VegaTheme.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isUser ? 'Вы' : 'Vega',
                      style: TextStyle(
                        color: isUser ? VegaTheme.accentBlue : VegaTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Actions
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    color: VegaTheme.textSecondary,
                    tooltip: 'Копировать',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                    onPressed: () => widget.onCopy(content),
                  ),
                  IconButton(
                    icon: const Icon(Icons.star_rounded, size: 17),
                    color: Colors.amber,
                    tooltip: 'Убрать из избранного',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                    onPressed: widget.onUnfavorite,
                  ),
                ],
              ),
            ),
            // Divider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Divider(
                height: 1,
                thickness: 1,
                color: VegaTheme.border.withOpacity(0.5),
              ),
            ),
            // Content with Markdown & optional max height
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Stack(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (isLong && !_expanded) ? 170.0 : double.infinity,
                    ),
                    child: ClipRect(
                      child: SelectionArea(
                        child: MarkdownBody(
                          data: content,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14, height: 1.55),
                            h1: const TextStyle(color: VegaTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                            h2: const TextStyle(color: VegaTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                            h3: const TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            strong: const TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold),
                            code: const TextStyle(
                              color: VegaTheme.accentBlue,
                              backgroundColor: Colors.transparent,
                              fontFamily: 'monospace',
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: VegaTheme.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isLong && !_expanded)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              VegaTheme.card.withOpacity(0.0),
                              VegaTheme.card.withOpacity(0.85),
                              VegaTheme.card,
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Expand / Collapse Toggle
            if (isLong)
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Свернуть' : 'Раскрыть полностью',
                        style: const TextStyle(
                          color: VegaTheme.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: VegaTheme.accent,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
