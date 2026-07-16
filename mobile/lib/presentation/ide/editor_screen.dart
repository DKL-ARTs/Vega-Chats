import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class EditorScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const EditorScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _client = ApiClient();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final SyntaxHighlightingController _codeCtrl;
  bool _loading = true;
  bool _isFullscreen = false;
  // === TABS STATE ===
  final List<Map<String, String>> _tabs = [];
  String _activePath = '';

  // === FILE EXPLORER STATE IN EDITOR ===
  String _currentPath = '/root/workspace';
  List<Map<String, dynamic>> _files = [];
  bool _filesLoading = false;
  String _fileSearchQuery = '';

  // === EDITOR SETTINGS STATE ===
  double _editorFontSize = 13.0;
  String _editorTheme = 'slate';
  bool _editorWordWrap = true;
  bool _editorShowLineNumbers = true;
  bool _editorAutoCloseBrackets = true;

  // === TERMINAL STATE ===
  bool _showTerminal = false;
  final List<Map<String, dynamic>> _terminals = [];
  int _activeTerminalIndex = 0;
  
  // === SEARCH & REPLACE STATE ===
  bool _showSearchBar = false;
  final _searchQueryCtrl = TextEditingController();
  final _replaceQueryCtrl = TextEditingController();
  List<int> _searchMatchOffsets = [];
  int _currentMatchIndex = -1;
  
  Timer? _debounceTimer;
  String _saveStatus = 'saved'; // 'saved' | 'saving' | 'error'
  String _lastSavedContent = '';

  @override
  void initState() {
    super.initState();
    _tabs.add({'path': widget.filePath, 'name': widget.fileName});
    _activePath = widget.filePath;
    
    _addNewTerminalTab();
    
    _codeCtrl = SyntaxHighlightingController(fileName: widget.fileName);
    _codeCtrl.addListener(_onCodeChanged);
    _searchQueryCtrl.addListener(_performSearch);
    _initAndLoad();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _codeCtrl.removeListener(_onCodeChanged);
    _searchQueryCtrl.removeListener(_performSearch);
    _codeCtrl.dispose();
    _searchQueryCtrl.dispose();
    _replaceQueryCtrl.dispose();
    
    for (final term in _terminals) {
      (term['channel'] as WebSocketChannel?)?.sink.close();
      (term['inputCtrl'] as TextEditingController).dispose();
      (term['scrollCtrl'] as ScrollController).dispose();
      (term['outputNotifier'] as ValueNotifier<List<String>>).dispose();
    }
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    _client.baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8765';
    
    setState(() {
      _editorFontSize = prefs.getDouble('editor_font_size') ?? 13.0;
      _editorTheme = prefs.getString('editor_theme') ?? 'slate';
      _editorWordWrap = prefs.getBool('editor_word_wrap') ?? true;
      _editorShowLineNumbers = prefs.getBool('editor_show_line_numbers') ?? true;
      _editorAutoCloseBrackets = prefs.getBool('editor_auto_close_brackets') ?? true;
    });

    await _loadTabFileContent(_activePath);
    await _loadExplorerFiles();
  }

  Future<void> _loadTabFileContent(String path) async {
    setState(() => _loading = true);
    try {
      final result = await _client.readFile(path);
      final content = result['content'] as String? ?? '';
      
      // Update syntax controller for the language extension
      final tabIndex = _tabs.indexWhere((t) => t['path'] == path);
      if (tabIndex != -1) {
        _codeCtrl.updateFileName(_tabs[tabIndex]['name'] ?? '');
      }
      
      _codeCtrl.text = content;
      _lastSavedContent = content;
      _activePath = path;
      
      if (_showSearchBar) {
        _performSearch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки файла: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExplorerFiles() async {
    setState(() => _filesLoading = true);
    try {
      final result = await _client.listFiles(_currentPath);
      setState(() {
        _files = List<Map<String, dynamic>>.from(result['items'] ?? []);
      });
    } catch (_) {
      setState(() => _files = []);
    } finally {
      setState(() => _filesLoading = false);
    }
  }

  Future<void> _openFileFromExplorer(Map<String, dynamic> item) async {
    final fullPath = '$_currentPath/${item['name']}';
    if (item['is_dir'] == true) {
      setState(() {
        _currentPath = fullPath;
      });
      await _loadExplorerFiles();
    } else {
      Navigator.pop(context); // Close endDrawer
      
      final existingTab = _tabs.indexWhere((t) => t['path'] == fullPath);
      if (existingTab == -1) {
        setState(() {
          _tabs.add({'path': fullPath, 'name': item['name']});
        });
      }
      await _loadTabFileContent(fullPath);
    }
  }

  void _addNewTerminalTab() {
    final nextId = _terminals.isEmpty ? 1 : (_terminals.last['id'] as int) + 1;
    final term = <String, dynamic>{
      'id': nextId,
      'name': 'Терминал $nextId',
      'inputCtrl': TextEditingController(),
      'scrollCtrl': ScrollController(),
      'outputNotifier': ValueNotifier<List<String>>([]),
      'channel': null,
      'connected': false,
    };
    setState(() {
      _terminals.add(term);
      _activeTerminalIndex = _terminals.length - 1;
    });
    if (_showTerminal) {
      _connectActiveTerminal();
    }
  }

  void _closeTerminalTab(int index) {
    final term = _terminals[index];
    final channel = term['channel'] as WebSocketChannel?;
    channel?.sink.close();
    (term['inputCtrl'] as TextEditingController).dispose();
    (term['scrollCtrl'] as ScrollController).dispose();
    (term['outputNotifier'] as ValueNotifier<List<String>>).dispose();
    
    setState(() {
      _terminals.removeAt(index);
      if (_activeTerminalIndex >= _terminals.length) {
        _activeTerminalIndex = _terminals.length - 1;
      }
      if (_terminals.isEmpty) {
        _showTerminal = false;
        _activeTerminalIndex = 0;
      }
    });
    
    if (_showTerminal && _terminals.isNotEmpty) {
      _connectActiveTerminal();
    }
  }

  Future<void> _connectActiveTerminal() async {
    if (_terminals.isEmpty) return;
    final term = _terminals[_activeTerminalIndex];
    if (term['connected'] == true) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      String baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8765';
      String wsUrl;
      if (baseUrl.startsWith('https://')) {
        wsUrl = 'wss://' + baseUrl.substring(8);
      } else if (baseUrl.startsWith('http://')) {
        wsUrl = 'ws://' + baseUrl.substring(7);
      } else {
        wsUrl = 'wss://' + baseUrl;
      }
      if (wsUrl.endsWith('/')) wsUrl = wsUrl.substring(0, wsUrl.length - 1);
      wsUrl += '/ws/terminal';

      final outputNotifier = term['outputNotifier'] as ValueNotifier<List<String>>;
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      term['channel'] = channel;
      
      channel.stream.listen(
        (data) {
          outputNotifier.value = List.from(outputNotifier.value)..add(data.toString());
          _scrollActiveTerminalToBottom();
        },
        onError: (e) {
          outputNotifier.value = List.from(outputNotifier.value)..add('Ошибка WebSocket: $e');
          setState(() {
            term['connected'] = false;
          });
        },
        onDone: () {
          outputNotifier.value = List.from(outputNotifier.value)..add('WebSocket соединение закрыто.');
          setState(() {
            term['connected'] = false;
          });
        },
      );
      setState(() {
        term['connected'] = true;
      });
    } catch (e) {
      final outputNotifier = term['outputNotifier'] as ValueNotifier<List<String>>;
      outputNotifier.value = List.from(outputNotifier.value)..add('Не удалось подключить терминал: $e');
      setState(() {
        term['connected'] = false;
      });
    }
  }

  void _scrollActiveTerminalToBottom() {
    if (_terminals.isEmpty) return;
    final term = _terminals[_activeTerminalIndex];
    final scrollCtrl = term['scrollCtrl'] as ScrollController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollCtrl.hasClients) {
        scrollCtrl.animateTo(
          scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendActiveTerminalCommand() {
    if (_terminals.isEmpty) return;
    final term = _terminals[_activeTerminalIndex];
    final inputCtrl = term['inputCtrl'] as TextEditingController;
    final cmd = inputCtrl.text.trim();
    final channel = term['channel'] as WebSocketChannel?;
    if (cmd.isEmpty || channel == null) return;
    
    channel.sink.add(cmd);
    inputCtrl.clear();
  }

  Widget _buildTerminalContent() {
    if (_terminals.isEmpty) {
      return const Center(child: Text('Нет активных терминалов', style: TextStyle(color: VegaTheme.textSecondary)));
    }

    final activeTerm = _terminals[_activeTerminalIndex];
    final outputNotifier = activeTerm['outputNotifier'] as ValueNotifier<List<String>>;
    final inputCtrl = activeTerm['inputCtrl'] as TextEditingController;
    final scrollCtrl = activeTerm['scrollCtrl'] as ScrollController;

    return Column(
      children: [
        Container(
          height: 32,
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _terminals.length,
                  itemBuilder: (ctx, index) {
                    final term = _terminals[index];
                    final isActive = index == _activeTerminalIndex;
                    final isTermConnected = term['connected'] == true;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeTerminalIndex = index;
                        });
                        _connectActiveTerminal();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF0F172A) : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: isActive ? VegaTheme.accent : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isTermConnected ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              term['name'] ?? '',
                              style: TextStyle(
                                color: isActive ? Colors.white : VegaTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _closeTerminalTab(index),
                              child: Icon(
                                Icons.close_rounded,
                                size: 12,
                                color: isActive ? Colors.white60 : Colors.white24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                onPressed: _addNewTerminalTab,
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tooltip: 'Создать сессию',
              ),
              const VerticalDivider(color: Colors.white10, width: 1, indent: 6, endIndent: 6),
              IconButton(
                onPressed: () {
                  outputNotifier.value = [];
                },
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white60, size: 16),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tooltip: 'Очистить вывод',
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showTerminal = false;
                  });
                },
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tooltip: 'Закрыть панель',
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: outputNotifier,
              builder: (context, lines, child) {
                return ListView.builder(
                  controller: scrollCtrl,
                  itemCount: lines.length,
                  itemBuilder: (ctx, i) {
                    final line = lines[i];
                    Color textCol = const Color(0xFFE2E8F0);
                    if (line.toLowerCase().contains('error') || line.toLowerCase().contains('failed')) {
                      textCol = Colors.redAccent;
                    } else if (line.toLowerCase().contains('warning')) {
                      textCol = Colors.amberAccent;
                    } else if (line.startsWith('\$ ') || line.startsWith('> ')) {
                      textCol = VegaTheme.accent;
                    }
                    
                    return Text(
                      line,
                      style: TextStyle(
                        color: textCol,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        Container(
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Text('\$ ', style: TextStyle(color: VegaTheme.accent, fontSize: 13, fontFamily: 'monospace')),
              Expanded(
                child: TextField(
                  controller: inputCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'Введите команду...',
                    hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onSubmitted: (_) => _sendActiveTerminalCommand(),
                ),
              ),
              IconButton(
                onPressed: _sendActiveTerminalCommand,
                icon: const Icon(Icons.send_rounded, color: VegaTheme.accent, size: 16),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onCodeChanged() {
    if (_codeCtrl.text == _lastSavedContent) {
      return;
    }
    setState(() {
      _saveStatus = 'saving';
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _autoSaveFile();
    });
  }

  Future<void> _autoSaveFile() async {
    final currentText = _codeCtrl.text;
    try {
      await _client.writeFile(_activePath, currentText);
      _lastSavedContent = currentText;
      if (mounted) {
        setState(() {
          _saveStatus = 'saved';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveStatus = 'error';
        });
      }
    }
  }

  Future<void> _saveFile() async {
    try {
      final text = _codeCtrl.text;
      await _client.writeFile(_activePath, text);
      _lastSavedContent = text;
      setState(() {
        _saveStatus = 'saved';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Файл успешно сохранен'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saveStatus = 'error';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _insertSymbol(String symbol) {
    final text = _codeCtrl.text;
    final selection = _codeCtrl.selection;
    
    int start = selection.start;
    int end = selection.end;
    
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, symbol);
    _codeCtrl.text = newText;
    
    // Position cursor after inserted symbol
    _codeCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: start + symbol.length),
    );
  }

  void _performSearch() {
    final query = _searchQueryCtrl.text;
    if (query.isEmpty) {
      setState(() {
        _searchMatchOffsets = [];
        _currentMatchIndex = -1;
      });
      return;
    }
    
    final text = _codeCtrl.text;
    final List<int> matches = [];
    int index = text.indexOf(query);
    while (index != -1) {
      matches.add(index);
      index = text.indexOf(query, index + query.length);
    }
    
    setState(() {
      _searchMatchOffsets = matches;
      if (matches.isNotEmpty) {
        // If current selection is not a match, default to first match
        if (_currentMatchIndex < 0 || _currentMatchIndex >= matches.length) {
          _currentMatchIndex = 0;
        }
        _selectMatch(_currentMatchIndex);
      } else {
        _currentMatchIndex = -1;
      }
    });
  }

  void _selectMatch(int matchIdx) {
    if (matchIdx < 0 || matchIdx >= _searchMatchOffsets.length) return;
    final start = _searchMatchOffsets[matchIdx];
    final end = start + _searchQueryCtrl.text.length;
    _codeCtrl.selection = TextSelection(baseOffset: start, extentOffset: end);
  }

  void _nextMatch() {
    if (_searchMatchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchMatchOffsets.length;
      _selectMatch(_currentMatchIndex);
    });
  }

  void _prevMatch() {
    if (_searchMatchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _searchMatchOffsets.length) % _searchMatchOffsets.length;
      _selectMatch(_currentMatchIndex);
    });
  }

  void _replaceCurrent() {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _searchMatchOffsets.length) return;
    final query = _searchQueryCtrl.text;
    final replacement = _replaceQueryCtrl.text;
    final start = _searchMatchOffsets[_currentMatchIndex];
    final end = start + query.length;
    
    final text = _codeCtrl.text;
    final newText = text.replaceRange(start, end, replacement);
    _codeCtrl.text = newText;
    
    _performSearch();
  }

  void _replaceAll() {
    final query = _searchQueryCtrl.text;
    if (query.isEmpty) return;
    final replacement = _replaceQueryCtrl.text;
    final text = _codeCtrl.text;
    final newText = text.replaceAll(query, replacement);
    _codeCtrl.text = newText;
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    final quickSymbols = ['{', '}', '[', ']', '(', ')', ';', '=', '<', '>', '/', '_', ':', '"', '\''];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: VegaTheme.dark,
      endDrawer: _buildExplorerDrawer(),
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: VegaTheme.dark,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _tabs.firstWhere((t) => t['path'] == _activePath, orElse: () => {'name': widget.fileName})['name'] ?? '',
                        style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      _buildSaveStatusIndicator(),
                    ],
                  ),
                  Text(
                    _activePath.length > 35 ? '...' + _activePath.substring(_activePath.length - 35) : _activePath,
                    style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  icon: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 24),
                  tooltip: 'Открыть файл',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 24),
                  color: VegaTheme.surface,
                  tooltip: 'ИИ Помощник',
                  onSelected: (action) {
                    final activeTabName = _tabs.firstWhere((t) => t['path'] == _activePath, orElse: () => {'name': widget.fileName})['name'] ?? '';
                    Navigator.pop(context, {
                      'action': action,
                      'path': _activePath,
                      'name': activeTabName,
                    });
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'explain',
                      child: Row(
                        children: [
                          Icon(Icons.psychology_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Объяснить код', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'tests',
                      child: Row(
                        children: [
                          Icon(Icons.science_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Написать тесты', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'refactor',
                      child: Row(
                        children: [
                          Icon(Icons.build_circle_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Рефакторинг', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'bugs',
                      child: Row(
                        children: [
                          Icon(Icons.bug_report_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Найти баги', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
                  icon: Icon(Icons.search_rounded, color: _showSearchBar ? VegaTheme.accent : Colors.white, size: 24),
                  tooltip: 'Поиск и замена',
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showTerminal = !_showTerminal;
                    });
                    if (_showTerminal) _connectActiveTerminal();
                  },
                  icon: Icon(Icons.terminal_rounded, color: _showTerminal ? VegaTheme.accent : Colors.white, size: 24),
                  tooltip: 'Терминал',
                ),
                IconButton(
                  onPressed: _showSettingsBottomSheet,
                  icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 24),
                  tooltip: 'Настройки редактора',
                ),
                IconButton(
                  onPressed: () => setState(() => _isFullscreen = true),
                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                  tooltip: 'Полноэкранный режим',
                ),
                IconButton(
                  onPressed: _saveFile,
                  icon: const Icon(Icons.save_rounded, color: VegaTheme.accent, size: 24),
                  tooltip: 'Сохранить',
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VegaTheme.accent))
          : SafeArea(
              child: Column(
                children: [
                  if (_isFullscreen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0xFF0F172A),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _tabs.firstWhere((t) => t['path'] == _activePath, orElse: () => {'name': widget.fileName})['name'] ?? '',
                                      style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildSaveStatusIndicator(),
                                  ],
                                ),
                                Text(
                                  _activePath.length > 30 ? '...' + _activePath.substring(_activePath.length - 30) : _activePath,
                                  style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 20),
                                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                                tooltip: 'Открыть файл',
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 20),
                                color: VegaTheme.surface,
                                tooltip: 'ИИ Помощник',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (action) {
                                  final activeTabName = _tabs.firstWhere((t) => t['path'] == _activePath, orElse: () => {'name': widget.fileName})['name'] ?? '';
                                  Navigator.pop(context, {
                                    'action': action,
                                    'path': _activePath,
                                    'name': activeTabName,
                                  });
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'explain',
                                    child: Row(
                                      children: [
                                        Icon(Icons.psychology_rounded, color: Colors.white, size: 16),
                                        SizedBox(width: 8),
                                        Text('Объяснить код', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'tests',
                                    child: Row(
                                      children: [
                                        Icon(Icons.science_rounded, color: Colors.white, size: 16),
                                        SizedBox(width: 8),
                                        Text('Написать тесты', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'refactor',
                                    child: Row(
                                      children: [
                                        Icon(Icons.build_circle_rounded, color: Colors.white, size: 16),
                                        SizedBox(width: 8),
                                        Text('Рефакторинг', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'bugs',
                                    child: Row(
                                      children: [
                                        Icon(Icons.bug_report_rounded, color: Colors.white, size: 16),
                                        SizedBox(width: 8),
                                        Text('Найти баги', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: Icon(Icons.search_rounded, color: _showSearchBar ? VegaTheme.accent : Colors.white, size: 20),
                                onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
                                tooltip: 'Поиск и замена',
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: Icon(Icons.terminal_rounded, color: _showTerminal ? VegaTheme.accent : Colors.white, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _showTerminal = !_showTerminal;
                                  });
                                  if (_showTerminal) _connectActiveTerminal();
                                },
                                tooltip: 'Терминал',
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 20),
                                onPressed: _showSettingsBottomSheet,
                                tooltip: 'Настройки редактора',
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: const Icon(Icons.save_rounded, color: VegaTheme.accent, size: 20),
                                onPressed: _saveFile,
                                tooltip: 'Сохранить',
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 20),
                                onPressed: () => setState(() => _isFullscreen = false),
                                tooltip: 'Выйти из полноэкранного режима',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (_showSearchBar)
                    _buildSearchBar(),
                  _buildTabBar(),
                  Expanded(
                    child: Container(
                      margin: _isFullscreen ? const EdgeInsets.all(2) : const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getEditorBgColor(),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VegaTheme.border, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left side line numbers panel (simple text builder based on lines count)
                          if (_editorShowLineNumbers)
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _codeCtrl,
                              builder: (context, value, child) {
                                final lineCount = '\n'.allMatches(value.text).length + 1;
                                final numberString = List.generate(lineCount, (i) => '${i + 1}').join('\n');
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                  color: _getLineNumbersBgColor(),
                                  child: Text(
                                    numberString,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: VegaTheme.textSecondary.withOpacity(0.5),
                                      fontFamily: 'monospace',
                                      fontSize: _editorFontSize - 1.0,
                                      height: 1.5,
                                    ),
                                  ),
                                );
                              },
                            ),
                          
                          // Code text area
                          Expanded(
                            child: _editorWordWrap
                                ? TextField(
                                    controller: _codeCtrl,
                                    maxLines: null,
                                    expands: true,
                                    inputFormatters: _editorAutoCloseBrackets ? [AutoCloseBracketsFormatter()] : [],
                                    style: TextStyle(
                                      color: _getCodeTextColor(),
                                      fontFamily: 'monospace',
                                      fontSize: _editorFontSize,
                                      height: 1.5,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.all(12),
                                      hintText: '// Пишите код здесь...',
                                      hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: 3000,
                                      child: TextField(
                                        controller: _codeCtrl,
                                        maxLines: null,
                                        expands: true,
                                        inputFormatters: _editorAutoCloseBrackets ? [AutoCloseBracketsFormatter()] : [],
                                        style: TextStyle(
                                          color: _getCodeTextColor(),
                                          fontFamily: 'monospace',
                                          fontSize: _editorFontSize,
                                          height: 1.5,
                                        ),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.all(12),
                                          hintText: '// Пишите код здесь...',
                                          hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showTerminal)
                  Container(
                    height: 180,
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VegaTheme.border, width: 0.5),
                    ),
                    child: _buildTerminalContent(),
                  ),
                
                // Quick coding symbols accessory bar above phone keyboard
                Container(
                  height: 44,
                  color: VegaTheme.surface,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: quickSymbols.length,
                    itemBuilder: (context, idx) {
                      final sym = quickSymbols[idx];
                      return GestureDetector(
                        onTap: () => _insertSymbol(sym),
                        child: Container(
                          width: 40,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          decoration: BoxDecoration(
                            color: VegaTheme.dark.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: VegaTheme.border.withOpacity(0.5), width: 0.5),
                          ),
                          child: Text(
                            sym,
                            style: const TextStyle(
                              color: VegaTheme.accent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSaveStatusIndicator() {
    Color dotColor;
    String text;
    if (_saveStatus == 'saving') {
      dotColor = Colors.orangeAccent;
      text = 'Сохранение...';
    } else if (_saveStatus == 'error') {
      dotColor = Colors.redAccent;
      text = 'Ошибка';
    } else {
      dotColor = Colors.greenAccent;
      text = 'Сохранено';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: VegaTheme.textSecondary.withOpacity(0.8), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final matchesCount = _searchMatchOffsets.length;
    final matchDisplay = matchesCount > 0 ? '${_currentMatchIndex + 1}/$matchesCount' : '0/0';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VegaTheme.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VegaTheme.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _searchQueryCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Найти...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                matchDisplay,
                style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _prevMatch,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                tooltip: 'Предыдущее совпадение',
              ),
              IconButton(
                onPressed: _nextMatch,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                tooltip: 'Следующее совпадение',
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showSearchBar = false;
                    _searchQueryCtrl.clear();
                  });
                },
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                tooltip: 'Закрыть поиск',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VegaTheme.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _replaceQueryCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Заменить на...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _replaceCurrent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VegaTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Заменить', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: _replaceAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Все', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 38,
      color: const Color(0xFF0F172A),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (ctx, index) {
          final tab = _tabs[index];
          final path = tab['path'] ?? '';
          final name = tab['name'] ?? '';
          final isActive = path == _activePath;

          return GestureDetector(
            onTap: () {
              if (!isActive) {
                _loadTabFileContent(path);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF1E293B) : Colors.transparent,
                border: Border(
                  right: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),
                  bottom: BorderSide(
                    color: isActive ? VegaTheme.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file_rounded,
                    size: 14,
                    color: isActive ? VegaTheme.accent : VegaTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      color: isActive ? Colors.white : VegaTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _closeTab(index);
                    },
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: isActive ? Colors.white60 : Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      Navigator.pop(context, true);
      return;
    }
    
    final closedTab = _tabs[index];
    final closedPath = closedTab['path'] ?? '';
    
    setState(() {
      _tabs.removeAt(index);
    });
    
    if (closedPath == _activePath) {
      final newIndex = index == 0 ? 0 : index - 1;
      final newActivePath = _tabs[newIndex]['path'] ?? '';
      _loadTabFileContent(newActivePath);
    }
  }

  Widget _buildExplorerDrawer() {
    return Drawer(
      backgroundColor: VegaTheme.dark,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Проводник файлов',
                    style: TextStyle(color: VegaTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: VegaTheme.textSecondary, size: 20),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: VegaTheme.surface,
              width: double.infinity,
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 14, color: VegaTheme.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _currentPath.length > 25 ? '...' + _currentPath.substring(_currentPath.length - 25) : _currentPath,
                      style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_currentPath != '/root/workspace')
                    GestureDetector(
                      onTap: () {
                        final parts = _currentPath.split('/');
                        parts.removeLast();
                        setState(() => _currentPath = parts.join('/'));
                        _loadExplorerFiles();
                      },
                      child: const Text('Назад', style: TextStyle(color: VegaTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: VegaTheme.surface,
              child: Container(
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VegaTheme.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.search_rounded, color: Colors.white38, size: 16),
                    ),
                    Expanded(
                      child: TextField(
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Поиск файлов...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _fileSearchQuery = val.trim().toLowerCase();
                          });
                        },
                      ),
                    ),
                    if (_fileSearchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _fileSearchQuery = '';
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _filesLoading
                  ? const Center(child: CircularProgressIndicator(color: VegaTheme.accent))
                  : () {
                      final filteredFiles = _files.where((f) {
                        final name = (f['name'] as String).toLowerCase();
                        return name.contains(_fileSearchQuery);
                      }).toList();
                      
                      return filteredFiles.isEmpty
                          ? const Center(child: Text('Ничего не найдено', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13)))
                          : ListView.builder(
                              itemCount: filteredFiles.length,
                              itemBuilder: (ctx, i) {
                                final item = filteredFiles[i];
                                final isDir = item['is_dir'] == true;
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                                    color: isDir ? VegaTheme.accent : VegaTheme.textSecondary,
                                    size: 18,
                                  ),
                                  title: Text(
                                    item['name'],
                                    style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 12.5),
                                  ),
                                  onTap: () => _openFileFromExplorer(item),
                                );
                              },
                            );
                    }(),
            ),
          ],
        ),
      ),
    );
  }

  Color _getEditorBgColor() {
    switch (_editorTheme) {
      case 'oled':
        return const Color(0xFF000000);
      case 'solarized':
        return const Color(0xFF002B36);
      case 'monokai':
        return const Color(0xFF272822);
      case 'slate':
      default:
        return const Color(0xFF0F172A);
    }
  }

  Color _getLineNumbersBgColor() {
    switch (_editorTheme) {
      case 'oled':
        return const Color(0xFF0C0C0C);
      case 'solarized':
        return const Color(0xFF073642);
      case 'monokai':
        return const Color(0xFF1E1F1C);
      case 'slate':
      default:
        return const Color(0xFF1E293B);
    }
  }

  Color _getCodeTextColor() {
    switch (_editorTheme) {
      case 'oled':
        return const Color(0xFFFFFFFF);
      case 'solarized':
        return const Color(0xFF839496);
      case 'monokai':
        return const Color(0xFFF8F8F2);
      case 'slate':
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VegaTheme.dark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Настройки редактора',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 20),
                    const Text('Тема оформления', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildThemeButton(setModalState, 'slate', 'Slate Dark', const Color(0xFF0F172A)),
                        _buildThemeButton(setModalState, 'oled', 'OLED Black', const Color(0xFF000000)),
                        _buildThemeButton(setModalState, 'solarized', 'Solarized', const Color(0xFF002B36)),
                        _buildThemeButton(setModalState, 'monokai', 'Monokai', const Color(0xFF272822)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Размер шрифта', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('${_editorFontSize.toInt()} px', style: const TextStyle(color: VegaTheme.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _editorFontSize,
                      min: 10,
                      max: 22,
                      divisions: 12,
                      activeColor: VegaTheme.accent,
                      inactiveColor: Colors.white10,
                      onChanged: (val) {
                        setModalState(() {
                          _editorFontSize = val;
                        });
                        setState(() {
                          _editorFontSize = val;
                        });
                        _saveSetting('editor_font_size', val);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Перенос строк (Word Wrap)', style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: _editorWordWrap,
                      activeColor: VegaTheme.accent,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setModalState(() {
                          _editorWordWrap = val;
                        });
                        setState(() {
                          _editorWordWrap = val;
                        });
                        _saveSetting('editor_word_wrap', val);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Показывать номера строк', style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: _editorShowLineNumbers,
                      activeColor: VegaTheme.accent,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setModalState(() {
                          _editorShowLineNumbers = val;
                        });
                        setState(() {
                          _editorShowLineNumbers = val;
                        });
                        _saveSetting('editor_show_line_numbers', val);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Автозакрытие скобок и кавычек', style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: _editorAutoCloseBrackets,
                      activeColor: VegaTheme.accent,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setModalState(() {
                          _editorAutoCloseBrackets = val;
                        });
                        setState(() {
                          _editorAutoCloseBrackets = val;
                        });
                        _saveSetting('editor_auto_close_brackets', val);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildThemeButton(StateSetter setModalState, String themeKey, String label, Color bg) {
    final isSelected = _editorTheme == themeKey;
    return GestureDetector(
      onTap: () {
        setModalState(() {
          _editorTheme = themeKey;
        });
        setState(() {
          _editorTheme = themeKey;
        });
        _saveSetting('editor_theme', themeKey);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? VegaTheme.accent : Colors.white24,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }
}

class AutoCloseBracketsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;

    // 1. Step-over feature: user typed a closing char that already exists right after the cursor
    if (newText.length == oldText.length + 1) {
      final oldEnd = oldValue.selection.end;
      if (oldEnd >= 0 && oldEnd < oldText.length) {
        final insertedChar = newText[oldEnd];
        final nextChar = oldText[oldEnd];
        if ((insertedChar == '}' && nextChar == '}') ||
            (insertedChar == ']' && nextChar == ']') ||
            (insertedChar == ')' && nextChar == ')') ||
            (insertedChar == '"' && nextChar == '"') ||
            (insertedChar == "'" && nextChar == "'")) {
          // Revert the insertion and just advance cursor by 1
          return oldValue.copyWith(
            selection: TextSelection.collapsed(offset: oldEnd + 1),
          );
        }
      }
    }

    // 2. Auto-close feature: user typed an opening bracket/quote
    if (newText.length == oldText.length + 1) {
      final oldEnd = oldValue.selection.end;
      if (oldEnd >= 0 && oldEnd < newText.length) {
        final insertedChar = newText[oldEnd];
        String? closingChar;
        if (insertedChar == '{') closingChar = '}';
        else if (insertedChar == '[') closingChar = ']';
        else if (insertedChar == '(') closingChar = ')';
        else if (insertedChar == '"') closingChar = '"';
        else if (insertedChar == "'") closingChar = "'";

        if (closingChar != null) {
          final prefix = newText.substring(0, oldEnd + 1);
          final suffix = newText.substring(oldEnd + 1);
          return TextEditingValue(
            text: '$prefix$closingChar$suffix',
            selection: TextSelection.collapsed(offset: oldEnd + 1),
          );
        }
      }
    }

    return newValue;
  }
}

class SyntaxHighlightingController extends TextEditingController {
  String fileName;

  SyntaxHighlightingController({required this.fileName, String? text}) : super(text: text);

  void updateFileName(String name) {
    fileName = name;
  }

  static final RegExp _jsDartPattern = RegExp(
    r'(//[^\n]*)|' // 1: Comments
    r'("(?:[^"\\]|\\.)*"|' // 2: Double-quoted strings
    r"'(?:[^'\\]|\\.)*')|" // 3: Single-quoted strings
    r'\b(const|let|var|function|class|return|if|else|for|while|import|export|from|new|this|await|async|void|null|true|false|final|extends|with|implements|factory|constructor|super|in|break|continue|switch|case|default|try|catch|finally|throw|rethrow|yield)\b|' // 4: Keywords
    r'\b(int|double|num|bool|String|List|Map|Set|DateTime|Future|Stream|dynamic)\b|' // 5: Types
    r'\b(\d+)\b', // 6: Numbers
  );

  static final RegExp _pyPattern = RegExp(
    r'(#[^\n]*)|' // 1: Comments
    r'("(?:[^"\\]|\\.)*"|' // 2: Double-quoted strings
    r"'(?:[^'\\]|\\.)*')|" // 3: Single-quoted strings
    r'\b(def|class|return|if|elif|else|for|while|import|from|as|in|is|and|or|not|try|except|finally|raise|print|len|range|str|int|float|list|dict|set|tuple|self|None|True|False)\b|' // 4: Keywords
    r'\b(\d+)\b', // 5: Numbers
  );

  static final RegExp _htmlPattern = RegExp(
    r'(<!--[\s\S]*?-->)|' // 1: HTML comments
    r'(<\/?[a-zA-Z0-9\-]+)|' // 2: Tag open/close name
    r'(\s[a-zA-Z0-9\-]+=)|' // 3: Attribute names
    r'("[^"]*"|' // 4: Double-quoted values
    r"'[^']*')|" // 5: Single-quoted values
    r'(>)', // 6: Tag closing bracket
  );

  static final RegExp _cssPattern = RegExp(
    r'(/\*[\s\S]*?\*/)|' // 1: Comments
    r'(\.[a-zA-Z\-0-9_]+|#[a-zA-Z\-0-9_]+|[a-zA-Z\-0-9_]+(?=\s*\{))|' // 2: Selector class, id or tag
    r'([a-zA-Z\-0-9_]+(?=\s*:))|' // 3: Property name
    r'("[^"]*"|' // 4: Strings
    r"'(?:[^'\\]|\\.)*')", // 5: Strings
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final ext = fileName.split('.').last.toLowerCase();
    RegExp pattern;
    if (ext == 'html' || ext == 'xml') {
      pattern = _htmlPattern;
    } else if (ext == 'css') {
      pattern = _cssPattern;
    } else if (ext == 'py') {
      pattern = _pyPattern;
    } else {
      pattern = _jsDartPattern;
    }

    final text = this.text;
    final matches = pattern.allMatches(text);
    if (matches.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final children = <TextSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        children.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }

      TextStyle? matchStyle;
      if (ext == 'html' || ext == 'xml') {
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null || match.group(6) != null) {
          matchStyle = const TextStyle(color: Color(0xFF7AA2F7)); // Blue tag name & brackets
        } else if (match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFFBB9AF3)); // Violet attribute name
        } else if (match.group(4) != null || match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A)); // Green string value
        }
      } else if (ext == 'css') {
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A), fontWeight: FontWeight.bold); // Green selector
        } else if (match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFF7AA2F7)); // Blue property name
        } else if (match.group(4) != null || match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFFFF9E64)); // Orange value string
        }
      } else if (ext == 'py') {
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null || match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A)); // Green string
        } else if (match.group(4) != null) {
          matchStyle = const TextStyle(color: Color(0xFFF7768E), fontWeight: FontWeight.bold); // Pink keyword
        } else if (match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFFFF9E64)); // Orange number
        }
      } else {
        // Default (JS/Dart/TS)
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null || match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A)); // Green string
        } else if (match.group(4) != null) {
          matchStyle = const TextStyle(color: Color(0xFFF7768E), fontWeight: FontWeight.bold); // Pink keyword
        } else if (match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFF7AA2F7)); // Blue type
        } else if (match.group(6) != null) {
          matchStyle = const TextStyle(color: Color(0xFFFF9E64)); // Orange number
        }
      }

      children.add(TextSpan(text: match.group(0), style: matchStyle));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      children.add(TextSpan(text: text.substring(lastIndex)));
    }

    return TextSpan(style: style, children: children);
  }
}
