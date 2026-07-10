import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../data/chat_history.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class ChatScreen extends StatefulWidget {
  final int? chatId;
  const ChatScreen({super.key, this.chatId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final _client = ApiClient();
  bool _loading = false;
  bool _cancelStream = false;
  final List<Map<String, dynamic>> _attachedFiles = [];
  String _model = 'openrouter/auto';
  int? _currentChatId;
  List<Map<String, dynamic>> _chats = [];
  Timer? _thinkingTimer;
  int _thinkingDots = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentChatId = widget.chatId;
    _loadSettings();
    _loadChats();
    if (_currentChatId != null) {
      _loadChat(_currentChatId!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload settings (model etc.) every time this screen becomes active
    // e.g. after returning from Settings page
    _loadSettings();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    _thinkingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
    // Normalize old URL (without 's') to the correct one
    if (baseUrl.contains('vega-chat-production') && !baseUrl.contains('vega-chats-production')) {
      baseUrl = 'https://vega-chats-production.up.railway.app';
      await prefs.setString('base_url', baseUrl);
    }
    setState(() {
      _model = prefs.getString('model') ?? 'openrouter/auto';
      _client.apiKey = prefs.getString('api_key') ?? '';
      _client.baseUrl = baseUrl;
    });
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
        // Restore filePaths/fileNames lists (new format)
        final rawPaths = msg['filePaths'];
        final rawNames = msg['fileNames'];
        _messages.add({
          'role': msg['role'] ?? '',
          'content': msg['content'] ?? '',
          'filePath': msg['filePath'] ?? '',
          'fileName': msg['fileName'] ?? '',
          'isImage': msg['isImage'] ?? false,
          'filePaths': rawPaths is List ? rawPaths.cast<String>() : <String>[],
          'fileNames': rawNames is List ? rawNames.cast<String>() : <String>[],
        });
      }
    });
  }

  void _startThinking() {
    _thinkingTimer?.cancel();
    _thinkingDots = 0;
    _thinkingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _thinkingDots = (_thinkingDots + 1) % 4;
        });
      }
    });
  }

  void _stopThinking() {
    _thinkingTimer?.cancel();
    _thinkingTimer = null;
    _thinkingDots = 0;
  }

  String get _thinkingText => 'Thinking' + '.' * _thinkingDots;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachedFiles.isEmpty) || _loading) return;
    final attachedSnapshot = List<Map<String, dynamic>>.from(_attachedFiles);
    _controller.clear();
    FocusScope.of(context).unfocus();
    await _loadSettings();

    // Build display text
    String displayText = text.isNotEmpty
        ? text
        : attachedSnapshot.map((f) => f['isImage'] == true ? '📷 ${f["name"]}' : '📎 ${f["name"]}').join(', ');

    if (_currentChatId == null) {
      _currentChatId = await ChatHistory.createChat(
        displayText.length > 30 ? displayText.substring(0, 30) + '...' : displayText,
      );
    }

    // Build message content — embed images as base64 markdown
    String msgContent = text;
    List<Map<String, String>> files = [];
    String firstFilePath = '';
    String firstFileName = '';
    bool firstIsImage = false;

    for (int i = 0; i < attachedSnapshot.length; i++) {
      final att = attachedSnapshot[i];
      final bytes = await File(att['path'] as String).readAsBytes();
      final name = att['name'] as String;
      final isImg = att['isImage'] == true;
      if (i == 0) { firstFilePath = att['path'] as String; firstFileName = name; firstIsImage = isImg; }
      if (isImg) {
        final ext = name.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : (ext == 'gif' ? 'image/gif' : 'image/jpeg');
        final b64 = base64Encode(bytes);
        msgContent = msgContent.isEmpty
            ? '![image](data:$mime;base64,$b64)'
            : '$msgContent\n\n![image](data:$mime;base64,$b64)';
      } else {
        files.add({'name': name, 'content': base64Encode(bytes)});
      }
    }

    // Collect all non-image file paths for display + persistence
    final List<String> allFilePaths = attachedSnapshot
        .where((f) => f['isImage'] != true)
        .map((f) => f['path'] as String)
        .toList();
    final List<String> allFileNames = attachedSnapshot
        .where((f) => f['isImage'] != true)
        .map((f) => f['name'] as String)
        .toList();

    await ChatHistory.addMessage(
      _currentChatId!, 'user', msgContent,
      filePath: firstFilePath, fileName: firstFileName, isImage: firstIsImage,
      filePaths: allFilePaths, fileNames: allFileNames,
    );
    await _loadChats();
    setState(() {
      _messages.add({
        'role': 'user', 'content': msgContent,
        'filePath': firstFilePath, 'fileName': firstFileName, 'isImage': firstIsImage,
        'filePaths': allFilePaths,
        'fileNames': allFileNames,
      });
      _attachedFiles.clear();
      _loading = true;
      _cancelStream = false;
    });
    _startThinking();
    try {
      final messagesForBackend = _messages.map((m) => {
        'role': m['role'].toString(),
        'content': m['content'].toString(),
      }).toList();
      setState(() { _messages.add({'role': 'assistant', 'content': ''}); });
      final responseBuffer = StringBuffer();
      bool firstChunk = true;
      await _client.streamChat(
        messages: messagesForBackend,
        model: _model,
        files: files.isEmpty ? null : files,
        onChunk: (chunk) {
          if (_cancelStream) return;
          if (firstChunk) { _stopThinking(); firstChunk = false; }
          responseBuffer.write(chunk);
          if (mounted) setState(() { _messages.last['content'] = responseBuffer.toString(); });
        },
        onError: (error) {
          _stopThinking();
          if (mounted) setState(() { _messages.last['content'] = 'Error: $error'; });
        },
      );
      _stopThinking();
      final finalResponse = responseBuffer.toString();
      if (_currentChatId != null && finalResponse.isNotEmpty) {
        await ChatHistory.addMessage(_currentChatId!, 'assistant', finalResponse);
      }
    } catch (e) {
      _stopThinking();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString(), style: TextStyle(fontSize: 9)), duration: Duration(seconds: 5)));
    } finally {
      if (mounted) setState(() { _loading = false; _cancelStream = false; });
    }
  }

  void _stopGeneration() {
    setState(() { _cancelStream = true; });
    _stopThinking();
  }

  Future<void> _regenerate(int assistantIndex) async {
    if (_loading) return;
    if (assistantIndex >= _messages.length || _messages[assistantIndex]['role'] != 'assistant') return;
    int userIndex = assistantIndex - 1;
    while (userIndex >= 0 && _messages[userIndex]['role'] != 'user') { userIndex--; }
    if (userIndex < 0) return;

    // Remove old assistant messages after the user message
    while (_messages.length > userIndex + 1) { _messages.removeLast(); }

    // Re-read ALL files from msg['filePaths'] (non-image files)
    List<Map<String, String>>? regenFiles;
    final userMsg = _messages[userIndex];
    final filePaths = userMsg['filePaths'] as List<String>? ?? [];
    final fileNames = userMsg['fileNames'] as List<String>? ?? [];
    // Legacy single-file support
    final singlePath = userMsg['filePath']?.toString() ?? '';
    final singleName = userMsg['fileName']?.toString() ?? 'file';
    if (filePaths.isNotEmpty) {
      regenFiles = [];
      for (int i = 0; i < filePaths.length; i++) {
        try {
          final bytes = await File(filePaths[i]).readAsBytes();
          regenFiles!.add({'name': fileNames.length > i ? fileNames[i] : 'file', 'content': base64Encode(bytes)});
        } catch (_) {}
      }
      if (regenFiles!.isEmpty) regenFiles = null;
    } else if (userMsg['isImage'] != true && singlePath.isNotEmpty) {
      // Legacy single-file fallback
      try {
        final bytes = await File(singlePath).readAsBytes();
        regenFiles = [{'name': singleName, 'content': base64Encode(bytes)}];
      } catch (_) {}
    }

    // Remove old assistant message from history
    if (_currentChatId != null) {
      await ChatHistory.removeLastAssistantMessage(_currentChatId!);
    }

    _stopThinking();
    setState(() { _loading = true; _messages.add({'role': 'assistant', 'content': ''}); });
    _startThinking();
    try {
      final msgs = _messages.sublist(0, userIndex + 1).map((m) =>
        {'role': m['role'].toString(), 'content': m['content'].toString()}).toList();
      final responseBuffer = StringBuffer();
      bool firstChunk = true;
      await _client.streamChat(
        messages: msgs,
        model: _model,
        files: regenFiles,
        onChunk: (chunk) {
          if (firstChunk) {
            _stopThinking();
            firstChunk = false;
          }
          responseBuffer.write(chunk);
          if (mounted) {
            setState(() {
              _messages.last['content'] = responseBuffer.toString();
            });
          }
        },
        onError: (error) {
          _stopThinking();
          if (mounted) {
            setState(() {
              _messages.last['content'] = 'Error: $error';
            });
          }
        },
      );
      _stopThinking();
      final finalResponse = responseBuffer.toString();
      if (_currentChatId != null && finalResponse.isNotEmpty) {
        await ChatHistory.addMessage(_currentChatId!, 'assistant', finalResponse);
      }
    } catch (e) {
      if (mounted) setState(() { _messages.last["content"] = "Error: $e"; });
    } finally {
      if (mounted) setState(() { _loading = false; _stopThinking(); });
    }
  }

    void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  void _showUserMessageMenu(BuildContext context, Map<String, dynamic> message, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VegaTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: VegaTheme.accent),
              title: Text('Edit', style: TextStyle(color: VegaTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _editMessage(index, message['content'] ?? '');
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: VegaTheme.accent),
              title: Text('Copy', style: TextStyle(color: VegaTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _copyMessage(message['content'] ?? '');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editMessage(int index, String currentText) {
    _controller.text = currentText;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Edit mode - type new message'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _deleteChat(int chatId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: Text('Delete chat?', style: TextStyle(color: VegaTheme.textPrimary)),
        content: Text('This action cannot be undone.', style: TextStyle(color: VegaTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await ChatHistory.deleteChat(chatId);
      await _loadChats();
      // If we deleted the current chat, go to new chat screen
      if (_currentChatId == chatId) {
        _startNewChat();
      }
    }
  }

  Future<String> _copyFileToAppDir(String sourcePath, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filesDir = Directory(p.join(appDir.path, 'chat_files'));
    if (!await filesDir.exists()) await filesDir.create(recursive: true);
    final ext = p.extension(fileName);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final newPath = p.join(filesDir.path, '$ts$ext');
    await File(sourcePath).copy(newPath);
    return newPath;
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
    if (result != null) {
      for (final f in result.files) {
        if (f.path == null) continue;
        final savedPath = await _copyFileToAppDir(f.path!, f.name);
        setState(() => _attachedFiles.add({'path': savedPath, 'name': f.name, 'isImage': false}));
      }
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    for (final image in images) {
      final savedPath = await _copyFileToAppDir(image.path, image.name);
      setState(() => _attachedFiles.add({'path': savedPath, 'name': image.name, 'isImage': true}));
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VegaTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Icons.photo_library, color: VegaTheme.accent), title: Text('Фото'), onTap: () { Navigator.pop(ctx); _pickImages(); }),
          ListTile(leading: Icon(Icons.insert_drive_file, color: VegaTheme.accent), title: Text('Файл'), onTap: () { Navigator.pop(ctx); _pickFiles(); }),
        ]),
      ),
    );
  }

  void _removeAttachment(int index) {
    setState(() => _attachedFiles.removeAt(index));
  }

  void _startNewChat() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    _stopThinking();
    _controller.clear();
    setState(() {
      _currentChatId = null;
      _messages.clear();
      _loading = false;
    });
  }

  void _openChat(int chatId) {
    _scaffoldKey.currentState?.closeDrawer();
    _stopThinking();
    setState(() {
      _currentChatId = chatId;
      _loading = false;
    });
    _loadChat(chatId);
  }

  bool get _showNewChatScreen => _messages.isEmpty && !_loading;

  String _stripImageMarkdown(String text) {
    return text.replaceAll(RegExp(r'!\[image\]\([^)]+\)'), '').trim();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Доброй ночи 🌙';
    if (hour < 12) return 'Доброе утро ☀️';
    if (hour < 18) return 'Добрый день 👋';
    return 'Добрый вечер ✨';
  }

  Widget _buildWelcomeScreen() {
    final suggestions = [
      {'icon': '💻', 'text': 'Написать код', 'prompt': 'Помоги мне написать код на '},
      {'icon': '📚', 'text': 'Объяснить тему', 'prompt': 'Объясни мне простыми словами что такое '},
      {'icon': '✍️', 'text': 'Написать текст', 'prompt': 'Напиши текст на тему '},
      {'icon': '💡', 'text': 'Придумать идею', 'prompt': 'Придумай интересную идею для '},
    ];

    return Stack(
      children: [
        // Ambient glow background
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.7, -0.4),
                radius: 1.2,
                colors: [Color(0x147C4DFF), Color(0x00000000)],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.8, 0.6),
                radius: 1.0,
                colors: [Color(0x102196F3), Color(0x00000000)],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, 1.0),
                radius: 0.8,
                colors: [Color(0x0A00BCD4), Color(0x00000000)],
              ),
            ),
          ),
        ),
        // Content — positioned slightly above center
        Align(
          alignment: const Alignment(0, -0.15),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo from asset
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1.0),
                  duration: const Duration(milliseconds: 2000),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: VegaTheme.accent.withOpacity(0.25 * value),
                              blurRadius: 28 * value,
                              spreadRadius: 4 * value,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                // Greeting — main title
                Text(
                  _getGreeting(),
                  style: const TextStyle(
                    color: VegaTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Пишу код, ищу ошибки, отвечаю\nна вопросы и генерирую идеи',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: VegaTheme.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                // 2x2 suggestion grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.6,
                  children: suggestions.map((s) => GestureDetector(
                    onTap: () {
                      _controller.text = s['prompt']!;
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: VegaTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: VegaTheme.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Text(s['icon']!, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(s['text']!, style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Parses ALL base64 images from message content and returns
  /// a horizontally scrollable strip. Uses RepaintBoundary + ValueKey
  /// to prevent flickering when parent setState is called during streaming.
  Widget _buildImagesRow(Map<String, dynamic> msg) {
    final content = (msg['content'] ?? '') as String;
    final pattern = RegExp(r'!\[image\]\(data:([^;]+);base64,([^)]+)\)');
    final matches = pattern.allMatches(content).toList();

    if (matches.isNotEmpty) {
      if (matches.length == 1) {
        final b64 = matches.first.group(2)!;
        return RepaintBoundary(
          key: ValueKey('img_${b64.substring(0, b64.length.clamp(0, 20))}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(b64),
              width: 250, fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: VegaTheme.textSecondary),
            ),
          ),
        );
      }

      // Multiple images — horizontal scroll
      return RepaintBoundary(
        key: ValueKey('imgs_${matches.length}'),
        child: SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final b64 = matches[i].group(2)!;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(b64),
                  width: 160, height: 180, fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: VegaTheme.textSecondary),
                ),
              );
            },
          ),
        ),
      );
    }

    // Fallback: single image from file path
    final filePath = (msg['filePath'] ?? '') as String;
    if (filePath.isNotEmpty && msg['isImage'] == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(filePath), width: 250, fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: VegaTheme.textSecondary)),
      );
    }

    return const SizedBox.shrink();
  }

  /// Builds a horizontal scrollable row of non-image file chips.
  Widget _buildFileChips(Map<String, dynamic> msg) {
    final fileNames = msg['fileNames'] as List<dynamic>?;
    final fileNamesLegacy = msg['fileName'] as String?;

    final names = fileNames != null && fileNames.isNotEmpty
        ? fileNames.cast<String>()
        : (fileNamesLegacy != null && fileNamesLegacy.isNotEmpty && msg['isImage'] != true
            ? [fileNamesLegacy]
            : <String>[]);

    if (names.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: names.map((name) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: VegaTheme.card.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 15),
            const SizedBox(width: 5),
            Text(name, style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 12)),
          ]),
        )).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
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
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(_isSearching ? Icons.close : Icons.search, color: VegaTheme.textSecondary, size: 22),
                          onPressed: () {
                            setState(() {
                              _isSearching = !_isSearching;
                              if (!_isSearching) {
                                _searchController.clear();
                                _searchQuery = '';
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.add, color: VegaTheme.accent),
                          onPressed: _startNewChat,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search chats...',
                      hintStyle: TextStyle(color: VegaTheme.textSecondary),
                      filled: true,
                      fillColor: VegaTheme.card,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      prefixIcon: Icon(Icons.search, color: VegaTheme.textSecondary, size: 20),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                  ),
                ),
              Expanded(
                child: _chats.isEmpty
                    ? Center(child: Text('No chats yet', style: TextStyle(color: VegaTheme.textSecondary)))
                    : Builder(builder: (ctx) {
                        final filtered = _searchQuery.isEmpty
                            ? _chats
                            : _chats.where((c) => (c['title'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();
                        if (filtered.isEmpty) {
                          return Center(child: Text('Nothing found', style: TextStyle(color: VegaTheme.textSecondary)));
                        }
                        return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final chat = filtered[i];
                          final isActive = chat['id'] == _currentChatId;
                          return ListTile(
                            selected: isActive,
                            selectedTileColor: VegaTheme.card,
                            leading: Icon(Icons.chat_bubble_outline, color: isActive ? VegaTheme.accent : VegaTheme.textSecondary),
                            title: Text(chat['title'] ?? 'Untitled', style: TextStyle(color: isActive ? VegaTheme.accent : VegaTheme.textPrimary)),
                            subtitle: Text(chat['createdAt']?.toString().substring(0, 10) ?? '', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: VegaTheme.textSecondary, size: 20),
                              onPressed: () => _deleteChat(chat['id']),
                            ),
                            onTap: () => _openChat(chat['id']),
                          );
                        },
                      );
                      }),
              ),
              Divider(color: VegaTheme.border),
              ListTile(
                leading: Icon(Icons.folder_outlined, color: VegaTheme.accent),
                title: Text('Files', style: TextStyle(color: VegaTheme.textPrimary)),
                onTap: () { _scaffoldKey.currentState?.closeDrawer(); context.push('/ide'); },
              ),
              ListTile(
                leading: Icon(Icons.terminal, color: VegaTheme.accent),
                title: Text('Terminal', style: TextStyle(color: VegaTheme.textPrimary)),
                onTap: () { _scaffoldKey.currentState?.closeDrawer(); context.push('/terminal'); },
              ),
              ListTile(
                leading: Icon(Icons.settings_outlined, color: VegaTheme.accent),
                title: Text('Settings', style: TextStyle(color: VegaTheme.textPrimary)),
                onTap: () { _scaffoldKey.currentState?.closeDrawer(); context.push('/settings'); },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        titleSpacing: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: VegaTheme.textSecondary),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: VegaTheme.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: VegaTheme.accent),
              ),
              const SizedBox(width: 6),
              Text(
                _model.split('/').last,
                style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          if (!_showNewChatScreen)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                onPressed: _startNewChat,
                tooltip: 'Новый чат',
                icon: SizedBox(
                  width: 24, height: 24,
                  child: Stack(
                    children: [
                      // Rounded square border
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          border: Border.all(color: VegaTheme.textSecondary, width: 1.8),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      // Pencil centered inside
                      const Positioned(
                        right: 1, bottom: 1,
                        child: Icon(Icons.edit, color: VegaTheme.textSecondary, size: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _showNewChatScreen
                ? _buildWelcomeScreen()
                : GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_loading ? 1 : 0),
                      itemBuilder: (ctx, i) {
                      if (_loading && i == _messages.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12, top: 4),
                            child: Text(_thinkingText, style: TextStyle(color: VegaTheme.textSecondary, fontSize: 15, fontStyle: FontStyle.italic)),
                          ),
                        );
                      }
                      if (i >= _messages.length) return const SizedBox.shrink();
                      final msg = _messages[i];
                      final isUser = msg['role'] == 'user';
                      return Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onLongPress: () {
                              if (isUser) {
                                _showUserMessageMenu(context, msg, i);
                              }
                            },
                            child: Column(
                              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (msg['isImage'] == true || (msg['content'] as String? ?? '').contains('base64,'))
                                   Container(
                                     margin: const EdgeInsets.only(bottom: 8),
                                     child: _buildImagesRow(msg),
                                   ),
                                 // Non-image files — show chips for ALL files
                                 if (msg['role'] == 'user' && msg['isImage'] != true && (
                                   (msg['filePaths'] as List<dynamic>?)?.isNotEmpty == true ||
                                   ((msg['filePath'] ?? '') as String).isNotEmpty
                                 ))
                                   Padding(
                                     padding: const EdgeInsets.only(bottom: 8),
                                     child: _buildFileChips(msg),
                                   ),
                                // Text message
                                if (_stripImageMarkdown(msg['content'] ?? '').isNotEmpty)
                                  isUser
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          margin: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: VegaTheme.userBubble,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(_stripImageMarkdown(msg['content'] ?? ''), style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 15)),
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                                          child: MarkdownBody(
                                            selectable: true,
                                            data: _stripImageMarkdown(msg['content'] ?? ''),
                                            shrinkWrap: true,
                                            styleSheet: MarkdownStyleSheet(
                                              p: TextStyle(color: VegaTheme.textPrimary, fontSize: 15, height: 1.6),
                                              h1: TextStyle(color: VegaTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
                                              h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
                                              h2: TextStyle(color: VegaTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold, height: 1.3),
                                              h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
                                              h3: TextStyle(color: VegaTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold, height: 1.3),
                                              h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
                                              strong: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold),
                                              em: TextStyle(color: VegaTheme.textPrimary, fontStyle: FontStyle.italic),
                                              blockSpacing: 14,
                                              code: TextStyle(color: VegaTheme.accent, backgroundColor: VegaTheme.surface, fontFamily: 'monospace', fontSize: 13),
                                              codeblockDecoration: BoxDecoration(color: VegaTheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: VegaTheme.border)),
                                              codeblockPadding: const EdgeInsets.all(14),
                                              blockquoteDecoration: BoxDecoration(color: VegaTheme.surface, borderRadius: BorderRadius.circular(4), border: Border(left: BorderSide(color: VegaTheme.accent, width: 3))),
                                              blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                                              horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: VegaTheme.border, width: 1))),
                                              listBullet: TextStyle(color: VegaTheme.accent, fontSize: 15, fontWeight: FontWeight.bold),
                                              listBulletPadding: const EdgeInsets.only(right: 6),
                                              listIndent: 20,
                                              tableHead: TextStyle(color: VegaTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                              tableBody: TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                                              tableBorder: TableBorder.all(color: VegaTheme.border, width: 0.5),
                                              tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              a: const TextStyle(color: VegaTheme.accent, decoration: TextDecoration.underline),
                                            ),
                                          ),
                                        ),
                              ],
                            ),
                          ),
                          if (!isUser && msg['content']?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12, left: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => _copyMessage(_stripImageMarkdown(msg['content'] ?? '')),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(Icons.copy, size: 16, color: VegaTheme.textSecondary),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _regenerate(i),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(Icons.refresh, size: 16, color: VegaTheme.textSecondary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  ),
          ),
          if (_attachedFiles.isNotEmpty)
            Container(
              height: 80,
              color: VegaTheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _attachedFiles.length,
                itemBuilder: (ctx, i) {
                  final att = _attachedFiles[i];
                  final isImg = att['isImage'] == true;
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        isImg
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(att['path'] as String), width: 64, height: 64, fit: BoxFit.cover),
                            )
                          : Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(color: VegaTheme.card, borderRadius: BorderRadius.circular(8)),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 24),
                                const SizedBox(height: 2),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    att['name'] as String,
                                    style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 9),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ]),
                            ),
                        Positioned(
                          top: -6, right: -6,
                          child: GestureDetector(
                            onTap: () => _removeAttachment(i),
                            child: Container(
                              width: 18, height: 18,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: VegaTheme.dark,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: SafeArea(
              top: false,
              child: Row(children: [
                IconButton(icon: Icon(Icons.add, color: VegaTheme.textSecondary, size: 26), onPressed: _showAttachMenu),
                Expanded(child: TextField(
                  controller: _controller,
                  style: TextStyle(color: VegaTheme.textPrimary, fontSize: 15),
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Сообщение...',
                    hintStyle: TextStyle(color: VegaTheme.textSecondary),
                    filled: true,
                    fillColor: VegaTheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onSubmitted: (_) => _send(),
                )),
                const SizedBox(width: 8),
                _loading
                  ? GestureDetector(
                      onTap: _stopGeneration,
                      child: Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: VegaTheme.accent, width: 2),
                        ),
                        child: const Icon(Icons.stop_rounded, color: VegaTheme.accent, size: 22),
                      ),
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF7C4DFF), Color(0xFF5C6BC0)],
                        ),
                      ),
                      child: IconButton(
                        onPressed: _send,
                        icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
                      ),
                    ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
