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
import 'package:http/http.dart' as http;
import 'package:open_file_plus/open_file_plus.dart';
import 'package:markdown/markdown.dart' as md;

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
  bool _isTyping = false; // tracks whether user has typed anything
  final Map<String, String> _fileDownloadStatus = {}; // tracks 'path' -> 'idle' | 'loading' | 'success'

  @override
  void initState() {
    super.initState();
    _currentChatId = widget.chatId;
    _loadSettings();
    _loadChats();
    if (_currentChatId != null) {
      _loadChat(_currentChatId!);
    }
    _controller.addListener(() {
      final typing = _controller.text.isNotEmpty;
      if (typing != _isTyping) setState(() => _isTyping = typing);
    });
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

  Future<void> _handleLinkTap(String url) async {
    if (url.contains('/api/files/download')) {
      final uri = Uri.parse(url);
      final filePathParam = uri.queryParameters['path'] ?? 'downloaded_file';
      final fileName = p.basename(filePathParam);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Скачивание файла $fileName...')),
      );

      try {
        final fullUrl = url.startsWith('/') ? '${_client.baseUrl}$url' : url;
        final response = await http.get(
          Uri.parse(fullUrl),
          headers: _client.apiKey.isNotEmpty ? {'Authorization': 'Bearer ${_client.apiKey}'} : {},
        );

        if (response.statusCode == 200) {
          Directory? downloadDir;
          if (Platform.isAndroid) {
            downloadDir = Directory('/storage/emulated/0/Download');
            if (!downloadDir.existsSync()) {
              downloadDir = Directory('/sdcard/Download');
            }
          }
          if (downloadDir == null || !downloadDir.existsSync()) {
            downloadDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
          }

          final savePath = p.join(downloadDir.path, fileName);
          final file = File(savePath);
          await file.writeAsBytes(response.bodyBytes);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Файл сохранен: $savePath'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка скачивания: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } else {
      await Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
      );
    }
  }

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
                // Logo, greeting, subtitle — always visible
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
                const SizedBox(height: 10),
                // Greeting + subtitle — hidden while typing
                if (!_isTyping) ...[
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
                  const SizedBox(height: 8),
                  // 2x2 suggestion grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
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
                ], // end if !_isTyping
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

  /// Parses list of generated files from assistant content.
  List<Map<String, String>> _extractGeneratedFiles(String content) {
    final List<Map<String, String>> list = [];
    final pattern = RegExp(r'\[([^\]]*?)\]\(/api/files/download\?path=([^)]+)\)');
    for (final match in pattern.allMatches(content)) {
      final name = match.group(1) ?? 'file';
      final path = match.group(2) ?? '';
      if (path.isNotEmpty) {
        // Extract original name from text (e.g. "Скачать filename" or "Скачать `filename`" -> "filename")
        String cleanName = name.replaceAll('Скачать ', '').replaceAll('файл ', '').replaceAll('`', '').trim();
        list.add({'name': cleanName, 'path': path});
      }
    }
    return list;
  }

  /// Cleans the raw file download markdown block from assistant message content.
  String _cleanMessageContent(String content) {
    String cleaned = content;
    // Strip write file tags
    cleaned = cleaned.replaceAll(RegExp(r'\[WRITE_FILE:.*?\]'), '');
    cleaned = cleaned.replaceAll('[/WRITE_FILE]', '');
    cleaned = cleaned.replaceAll(RegExp(r'WRITE_FILE:.*?\]'), '');
    // Strip markdown code blocks
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // Strip download links
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*?\]\(/api/files/download\?path=[^)]+\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'Вы можете\s*$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'Вы можете\s*\n'), '');
    cleaned = cleaned.replaceAll(RegExp(r'### 💾 Создан файл.*?\n'), '');
    cleaned = cleaned.replaceAll(RegExp(r'### 💾 Создан файл.*?$'), '');
    return cleaned.trim();
  }

  /// Opens the generated file directly using native Android intent chooser (always fetches fresh content).
  void _openGeneratedFile(String path, String name) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final localFile = File(p.join(tempDir.path, name));
      
      // Always fetch fresh content to bypass persistent local cache bugs
      final result = await _client.readFile(path);
      final content = result['content'] ?? '';
      await localFile.writeAsString(content, encoding: utf8);
      
      final openResult = await OpenFile.open(localFile.path);
      if (openResult.type != ResultType.done) {
        throw Exception(openResult.message);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть файл: $e')),
      );
    }
  }

  /// Downloads the generated file to the standard Downloads folder (sequential fallbacks for modern Android).
  Future<void> _downloadGeneratedFile(String filePath, String fileName) async {
    setState(() {
      _fileDownloadStatus[filePath] = 'loading';
    });

    try {
      final downloadUrl = '/api/files/download?path=$filePath';
      final fullUrl = '${_client.baseUrl}$downloadUrl';
      final response = await http.get(
        Uri.parse(fullUrl),
        headers: _client.apiKey.isNotEmpty ? {'Authorization': 'Bearer ${_client.apiKey}'} : {},
      );

      if (response.statusCode == 200) {
        List<String> targetDirs = [];
        if (Platform.isAndroid) {
          targetDirs.add('/storage/emulated/0/Download');
          targetDirs.add('/storage/emulated/0/Vega_Chat');
          targetDirs.add('/sdcard/Download');
        }
        
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) targetDirs.add(extDir.path);
        final docDir = await getApplicationDocumentsDirectory();
        targetDirs.add(docDir.path);

        bool success = false;
        for (final dirPath in targetDirs) {
          final dir = Directory(dirPath);
          try {
            if (!dir.existsSync()) {
              dir.createSync(recursive: true);
            }
            final file = File(p.join(dir.path, fileName));
            await file.writeAsBytes(response.bodyBytes);
            success = true;
            break;
          } catch (e) {
            print('Failed to write to $dirPath: $e');
          }
        }

        if (success) {
          setState(() {
            _fileDownloadStatus[filePath] = 'success';
          });
        } else {
          throw Exception('Не удалось сохранить файл. Пожалуйста, разрешите доступ к памяти в настройках Vega Chat.');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _fileDownloadStatus[filePath] = 'idle';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка скачивания: $e')),
      );
    }
  }

  /// Builds a custom generated file card (looks exactly like picked files).
  Widget _buildGeneratedFileCard(String fileName, String filePath) {
    final status = _fileDownloadStatus[filePath] ?? 'idle';
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VegaTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VegaTheme.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: VegaTheme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Generated File',
                      style: TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _openGeneratedFile(filePath, fileName),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Открыть'),
                  style: TextButton.styleFrom(
                    foregroundColor: VegaTheme.textPrimary,
                    backgroundColor: VegaTheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: status == 'loading' ? null : () => _downloadGeneratedFile(filePath, fileName),
                  icon: status == 'loading'
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: VegaTheme.accent),
                        )
                      : Icon(
                          status == 'success' ? Icons.check : Icons.download,
                          color: status == 'success' ? Colors.green : VegaTheme.accent,
                          size: 16,
                        ),
                  label: Text(
                    status == 'loading'
                        ? 'Скачивание...'
                        : (status == 'success' ? 'Скачано' : 'Скачать'),
                    style: TextStyle(
                      color: status == 'success' ? Colors.green : VegaTheme.textPrimary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: VegaTheme.textPrimary,
                    backgroundColor: VegaTheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds a horizontal scrollable row of non-image file chips (large, like single-file).
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
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: VegaTheme.card.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 28),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.length > 20 ? name.substring(0, 20) + '…' : name,
                  style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text('File', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 11)),
              ],
            ),
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
      extendBodyBehindAppBar: true,
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
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
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed: _startNewChat,
                tooltip: 'Новый чат',
                icon: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Dog-ear square (note icon)
                    Icon(Icons.note_alt_outlined, color: VegaTheme.textSecondary, size: 26),
                    // Small pencil at bottom-right
                    Positioned(
                      right: -2, bottom: -2,
                      child: Container(
                        decoration: BoxDecoration(
                          color: VegaTheme.dark,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(1),
                        child: Icon(Icons.edit, color: VegaTheme.accent, size: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _showNewChatScreen
                ? _buildWelcomeScreen()
                : GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                        16,
                        16 + 70 + (_attachedFiles.isNotEmpty ? 88 : 0),
                      ),
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
                                 if (msg['role'] == 'user' && msg['isImage'] != true && (
                                   (msg['filePaths'] as List<dynamic>?)?.isNotEmpty == true ||
                                   ((msg['filePath'] ?? '') as String).isNotEmpty
                                 ))
                                   Padding(
                                     padding: const EdgeInsets.only(bottom: 8),
                                     child: _buildFileChips(msg),
                                   ),
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
                                           child: Column(
                                             crossAxisAlignment: CrossAxisAlignment.start,
                                             mainAxisSize: MainAxisSize.min,
                                             children: [
                                               MarkdownBody(
                                                 selectable: true,
                                                 data: _stripImageMarkdown(_cleanMessageContent(msg['content'] ?? '')),
                                                 shrinkWrap: true,
                                                 onTapLink: (text, href, title) {
                                                   if (href != null) {
                                                     _handleLinkTap(href);
                                                   }
                                                 },
                                                 builders: {
                                                   'pre': CodeBlockBuilder(),
                                                 },
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
                                                   codeblockDecoration: const BoxDecoration(color: Colors.transparent),
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
                                               ..._extractGeneratedFiles(msg['content'] ?? '').map((file) {
                                                 final fileName = file['name'] ?? 'file';
                                                 final filePath = file['path'] ?? '';
                                                 return _buildGeneratedFileCard(fileName, filePath);
                                               }).toList(),
                                             ],
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
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      VegaTheme.dark,
                      VegaTheme.dark.withOpacity(0.85),
                      VegaTheme.dark.withOpacity(0),
                    ],
                    stops: const [0.0, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      VegaTheme.dark,
                      VegaTheme.dark.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                                      const SizedBox(height: 10),
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
                // Input bar — transparent background
                Container(
                  decoration: const BoxDecoration(color: Colors.transparent),
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
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
                        : Builder(builder: (ctx) {
                            final hasContent = _controller.text.trim().isNotEmpty || _attachedFiles.isNotEmpty;
                            return Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: hasContent
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF7C4DFF), Color(0xFF5C6BC0)],
                                    )
                                  : null,
                                color: hasContent ? null : VegaTheme.surface,
                              ),
                              child: IconButton(
                                onPressed: hasContent ? _send : null,
                                icon: Icon(Icons.arrow_upward_rounded,
                                  color: hasContent ? Colors.white : VegaTheme.textSecondary,
                                  size: 22),
                              ),
                            );
                          }),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom markdown element builder for block code with Copy button and language tag.
class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder();

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final textContent = element.textContent;
    String language = 'code';
    if (element.children != null && element.children!.isNotEmpty) {
      final child = element.children!.first;
      if (child is md.Element && child.attributes.containsKey('class')) {
        final className = child.attributes['class'] ?? '';
        if (className.startsWith('language-')) {
          language = className.substring(9);
        }
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: VegaTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VegaTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: VegaTheme.card.withOpacity(0.5),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: VegaTheme.border, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.toUpperCase(),
                  style: TextStyle(color: VegaTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                CopyButton(text: textContent),
              ],
            ),
          ),
          // Code Display
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                textContent.trimRight(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: VegaTheme.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A stateful Copy Button with a tap animation and transition to a checkmark on success.
class CopyButton extends StatefulWidget {
  final String text;
  const CopyButton({super.key, required this.text});

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  void _doCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _doCopy,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check : Icons.copy,
                size: 14,
                color: _copied ? Colors.green : VegaTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                _copied ? 'Copied!' : 'Copy',
                style: TextStyle(
                  color: _copied ? Colors.green : VegaTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
