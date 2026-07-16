import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/theme.dart';

// A single terminal session
class _TerminalSession {
  final String id;
  String name;
  final List<_TermLine> lines;
  final TextEditingController inputCtrl;
  final ScrollController scrollCtrl;
  final List<String> commandHistory;
  int historyIndex;
  WebSocketChannel? channel;
  bool connected;
  bool connecting;

  _TerminalSession({
    required this.id,
    required this.name,
  })  : lines = [],
        inputCtrl = TextEditingController(),
        scrollCtrl = ScrollController(),
        commandHistory = [],
        historyIndex = -1,
        connected = false,
        connecting = false;

  void dispose() {
    channel?.sink.close();
    inputCtrl.dispose();
    scrollCtrl.dispose();
  }
}

enum _LineType { system, command, output, error }

class _TermLine {
  final String text;
  final _LineType type;
  _TermLine(this.text, this.type);
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with TickerProviderStateMixin {
  final List<_TerminalSession> _sessions = [];
  late TabController _tabController;
  int _activeIndex = 0;
  String _wsBaseUrl = '';

  // Quick-access shortcuts
  final List<Map<String, String>> _shortcuts = [
    {'label': '📱 Телефон', 'cmd': 'cd /storage/emulated/0 && ls'},
    {'label': '🏠 Home', 'cmd': 'cd ~ && pwd'},
    {'label': '📁 Workspace', 'cmd': 'cd /root/workspace && ls'},
    {'label': '📋 Процессы', 'cmd': 'ps aux | head -20'},
    {'label': '💾 Диск', 'cmd': 'df -h'},
    {'label': '🧠 Память', 'cmd': 'free -h'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);
    _loadUrlAndConnect();
  }

  Future<void> _loadUrlAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    String baseUrl =
        prefs.getString('base_url') ?? 'http://127.0.0.1:8765';
    String wsUrl;
    if (baseUrl.startsWith('https://')) {
      wsUrl = 'wss://' + baseUrl.substring(8);
    } else if (baseUrl.startsWith('http://')) {
      wsUrl = 'ws://' + baseUrl.substring(7);
    } else {
      wsUrl = 'wss://' + baseUrl;
    }
    if (wsUrl.endsWith('/')) wsUrl = wsUrl.substring(0, wsUrl.length - 1);
    _wsBaseUrl = wsUrl + '/ws/terminal';
    _addSession();
  }

  void _addSession({String? name}) {
    final idx = _sessions.length + 1;
    final session = _TerminalSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name ?? 'Сессия $idx',
    );
    _sessions.add(session);
    _rebuildTabController(session.id);
    _connectSession(session);
  }

  void _rebuildTabController(String? focusId) {
    final oldController = _tabController;
    _tabController = TabController(
      length: _sessions.length,
      vsync: this,
      initialIndex: focusId != null
          ? _sessions.indexWhere((s) => s.id == focusId).clamp(0, _sessions.length - 1)
          : _activeIndex.clamp(0, _sessions.length - 1),
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _activeIndex = _tabController.index);
    });
    oldController.dispose();
    setState(() {
      _activeIndex = _tabController.index;
    });
  }

  Future<void> _connectSession(_TerminalSession session) async {
    if (_wsBaseUrl.isEmpty) return;
    setState(() {
      session.connecting = true;
      session.lines.add(_TermLine('Подключение к серверу...', _LineType.system));
    });

    try {
      session.channel = WebSocketChannel.connect(Uri.parse(_wsBaseUrl));
      session.channel!.stream.listen(
        (data) {
          if (!mounted) return;
          setState(() {
            session.lines.add(_TermLine(data.toString(), _LineType.output));
            _scrollToBottom(session);
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            session.connected = false;
            session.connecting = false;
            session.lines.add(_TermLine('⚠️ Ошибка: $e', _LineType.error));
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            session.connected = false;
            session.connecting = false;
            session.lines.add(_TermLine('— Соединение закрыто —', _LineType.system));
          });
        },
      );
      setState(() {
        session.connected = true;
        session.connecting = false;
        session.lines.add(_TermLine('✅ Подключено. Введите команду.', _LineType.system));
      });
    } catch (e) {
      setState(() {
        session.connected = false;
        session.connecting = false;
        session.lines.add(_TermLine('❌ Не удалось подключиться: $e', _LineType.error));
      });
    }
  }

  void _scrollToBottom(_TerminalSession session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (session.scrollCtrl.hasClients) {
        session.scrollCtrl.animateTo(
          session.scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendCommand(_TerminalSession session, [String? override]) {
    final cmd = override ?? session.inputCtrl.text.trim();
    if (cmd.isEmpty) return;
    if (session.channel == null || !session.connected) {
      setState(() {
        session.lines.add(_TermLine('⚠️ Нет соединения. Переподключаемся...', _LineType.system));
      });
      _connectSession(session);
      return;
    }
    session.channel!.sink.add(cmd);
    setState(() {
      session.commandHistory.insert(0, cmd);
      session.historyIndex = -1;
      session.lines.add(_TermLine('\$ $cmd', _LineType.command));
      _scrollToBottom(session);
    });
    if (override == null) session.inputCtrl.clear();
  }

  void _closeSession(int index) {
    if (_sessions.length <= 1) {
      // Don't close last session, just clear it
      setState(() {
        _sessions[0].lines.clear();
        _sessions[0].lines.add(_TermLine('Вывод очищен.', _LineType.system));
      });
      return;
    }
    _sessions[index].dispose();
    _sessions.removeAt(index);
    final newIdx = (index - 1).clamp(0, _sessions.length - 1);
    _rebuildTabController(_sessions[newIdx].id);
  }

  void _renameSession(int index) {
    final ctrl = TextEditingController(text: _sessions[index].name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: const Text('Переименовать сессию', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            hintText: 'Имя сессии',
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: VegaTheme.accent),
            onPressed: () {
              setState(() => _sessions[index].name = ctrl.text.trim().isNotEmpty ? ctrl.text.trim() : _sessions[index].name);
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _copyOutput(int index) {
    final text = _sessions[index].lines.map((l) => l.text).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Вывод скопирован'), duration: Duration(seconds: 1)),
    );
  }

  void _clearSession(int index) {
    setState(() {
      _sessions[index].lines.clear();
      _sessions[index].lines.add(_TermLine('Вывод очищен.', _LineType.system));
    });
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sessions.isEmpty) {
      return Scaffold(
        backgroundColor: VegaTheme.dark,
        body: const Center(child: CircularProgressIndicator(color: VegaTheme.accent)),
      );
    }

    final session = _sessions[_activeIndex.clamp(0, _sessions.length - 1)];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A),
      appBar: AppBar(
        backgroundColor: VegaTheme.surface,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.terminal_rounded, color: VegaTheme.accent, size: 18),
            SizedBox(width: 8),
            Text('Терминал', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Reconnect
          if (!session.connected)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: VegaTheme.accent),
              tooltip: 'Переподключить',
              onPressed: () => _connectSession(session),
            ),
          // Clear
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white38),
            tooltip: 'Очистить',
            onPressed: () => _clearSession(_activeIndex),
          ),
          // Copy all output
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white38),
            tooltip: 'Копировать вывод',
            onPressed: () => _copyOutput(_activeIndex),
          ),
          // Add session
          IconButton(
            icon: const Icon(Icons.add_rounded, color: VegaTheme.accent),
            tooltip: 'Новая сессия',
            onPressed: _addSession,
          ),
          // Status dot
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 2),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session.connected ? Colors.greenAccent : Colors.redAccent,
                  boxShadow: [
                    BoxShadow(
                      color: (session.connected ? Colors.greenAccent : Colors.redAccent).withOpacity(0.5),
                      blurRadius: 4,
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
        bottom: _sessions.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(38),
                child: Container(
                  color: const Color(0xFF0F172A),
                  height: 38,
                  child: Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          indicatorColor: VegaTheme.accent,
                          indicatorWeight: 2,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white38,
                          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          tabs: _sessions.asMap().entries.map((e) {
                            final i = e.key;
                            final s = e.value;
                            return Tab(
                              child: GestureDetector(
                                onLongPress: () => _renameSession(i),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6, height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: s.connected ? Colors.greenAccent : Colors.redAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(s.name),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => _closeSession(i),
                                      child: const Icon(Icons.close_rounded, size: 13, color: Colors.white38),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // Shortcuts bar
          Container(
            height: 36,
            color: VegaTheme.surface,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              itemCount: _shortcuts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final s = _shortcuts[i];
                return GestureDetector(
                  onTap: () => _sendCommand(session, s['cmd']),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: VegaTheme.border),
                    ),
                    child: Text(
                      s['label']!,
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              },
            ),
          ),

          // Terminal output
          Expanded(
            child: _sessions.length > 1
                ? TabBarView(
                    controller: _tabController,
                    children: _sessions.map((s) => _buildSessionOutput(s)).toList(),
                  )
                : _buildSessionOutput(session),
          ),

          // Input bar
          _buildInputBar(session),
        ],
      ),
    );
  }

  Widget _buildSessionOutput(_TerminalSession session) {
    return ListView.builder(
      controller: session.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: session.lines.length,
      itemBuilder: (ctx, i) {
        final line = session.lines[i];
        Color color;
        FontWeight weight = FontWeight.normal;

        switch (line.type) {
          case _LineType.system:
            color = Colors.white30;
            break;
          case _LineType.command:
            color = VegaTheme.accent;
            weight = FontWeight.bold;
            break;
          case _LineType.error:
            color = Colors.redAccent;
            break;
          case _LineType.output:
            // Colorize based on content
            final lower = line.text.toLowerCase();
            if (lower.contains('error') || lower.contains('failed') || lower.contains('ошибка')) {
              color = Colors.redAccent.shade100;
            } else if (lower.contains('warning') || lower.contains('warn')) {
              color = Colors.amber;
            } else if (lower.contains('success') || lower.contains('done') || lower.contains('ok')) {
              color = Colors.greenAccent.shade200;
            } else {
              color = const Color(0xFFE2E8F0);
            }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SelectableText(
            line.text,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.45,
              fontWeight: weight,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar(_TerminalSession session) {
    return Container(
      color: VegaTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // History navigation
              GestureDetector(
                onTap: () {
                  if (session.commandHistory.isEmpty) return;
                  setState(() {
                    session.historyIndex = (session.historyIndex + 1)
                        .clamp(0, session.commandHistory.length - 1);
                    session.inputCtrl.text = session.commandHistory[session.historyIndex];
                    session.inputCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: session.inputCtrl.text.length),
                    );
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.arrow_upward_rounded, color: Colors.white24, size: 18),
                ),
              ),

              // Prompt
              Text(
                session.connected ? '\$ ' : '✗ ',
                style: TextStyle(
                  color: session.connected ? VegaTheme.accent : Colors.redAccent,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),

              // Input field
              Expanded(
                child: TextField(
                  controller: session.inputCtrl,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Введите команду...',
                    hintStyle: TextStyle(color: Colors.white24, fontFamily: 'monospace', fontSize: 12),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _sendCommand(session),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.send,
                ),
              ),

              // Send button
              GestureDetector(
                onTap: () => _sendCommand(session),
                child: Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: session.connected ? VegaTheme.accent : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: session.connected ? Colors.white : Colors.white24,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),

          // Tab completion hint (Ctrl+C)
          if (session.connected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _termKey('Ctrl+C', () => _sendCommand(session, '\x03')),
                  const SizedBox(width: 6),
                  _termKey('Tab', () => _sendCommand(session, '\x09')),
                  const SizedBox(width: 6),
                  _termKey('↑ История', () {
                    if (session.commandHistory.isEmpty) return;
                    setState(() {
                      session.historyIndex = (session.historyIndex + 1)
                          .clamp(0, session.commandHistory.length - 1);
                      session.inputCtrl.text = session.commandHistory[session.historyIndex];
                    });
                  }),
                  const SizedBox(width: 6),
                  _termKey('Clear', () => _clearSession(_activeIndex)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _termKey(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ),
    );
  }
}
