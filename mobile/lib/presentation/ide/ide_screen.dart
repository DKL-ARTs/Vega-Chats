import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as speechToText;
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../data/chat_history.dart';
import '../chat/widgets/terminal_command_widget.dart';
import 'editor_screen.dart';

class IdeScreen extends StatefulWidget {
  const IdeScreen({super.key});

  @override
  State<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends State<IdeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _client = ApiClient();

  // === FILE EXPLORER STATE ===
  String _currentPath = '/root/workspace';
  List<Map<String, dynamic>> _files = [];
  bool _filesLoading = true;

  // === AI DEV CHAT STATE ===
  int? _ideChatId;
  List<Map<String, dynamic>> _chatMessages = [];
  final _chatInputCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  bool _chatLoading = false;
  bool _cancelStream = false;
  String _thinkingText = 'Кодер думает...';

  // === TERMINAL STATE ===
  final _termInputCtrl = TextEditingController();
  final _termScrollCtrl = ScrollController();
  final List<String> _termOutput = [];
  WebSocketChannel? _termChannel;
  bool _termConnected = false;

  // === SPEECH & ATTACHMENTS STATE ===
  final speechToText.SpeechToText _speechToText = speechToText.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';
  final List<Map<String, dynamic>> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initSpeech();
    _initSettingsAndData();
  }

  Future<void> _initSettingsAndData() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8765';
    final apiKey = prefs.getString('api_key') ?? '';
    setState(() {
      _client.baseUrl = baseUrl;
      _client.apiKey = apiKey;
    });
    
    await _loadFiles();
    await _initIdeChat();
    await _connectTerminal();
  }

  // ==========================================
  // === SPEECH & ATTACHMENTS LOGIC ===
  // ==========================================
  Future<void> _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (val) => debugPrint('Speech initialization error: $val'),
        onStatus: (val) {
          debugPrint('Speech status: $val');
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Speech init exception: $e');
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      await _initSpeech();
    }
    if (_speechEnabled) {
      setState(() => _isListening = true);
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords;
            if (_lastWords.isNotEmpty) {
              _chatInputCtrl.text = _lastWords;
              _chatInputCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _chatInputCtrl.text.length),
              );
            }
          });
        },
        listenMode: speechToText.ListenMode.dictation,
        pauseFor: const Duration(seconds: 5),
      );
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }

  Future<String> _copyFileToAppDir(String sourcePath, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filesDir = Directory(p.join(appDir.path, 'attached_files'));
    if (!await filesDir.exists()) {
      await filesDir.create(recursive: true);
    }
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
          ListTile(leading: Icon(Icons.photo_library, color: VegaTheme.accent), title: const Text('Фото'), onTap: () { Navigator.pop(ctx); _pickImages(); }),
          ListTile(leading: Icon(Icons.insert_drive_file, color: VegaTheme.accent), title: const Text('Файл'), onTap: () { Navigator.pop(ctx); _pickFiles(); }),
        ]),
      ),
    );
  }

  void _removeAttachment(int index) {
    setState(() => _attachedFiles.removeAt(index));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatInputCtrl.dispose();
    _chatScrollCtrl.dispose();
    _termInputCtrl.dispose();
    _termScrollCtrl.dispose();
    _termChannel?.sink.close();
    super.dispose();
  }

  // ==========================================
  // === FILE EXPLORER LOGIC ===
  // ==========================================
  Future<void> _loadFiles() async {
    setState(() => _filesLoading = true);
    try {
      final result = await _client.listFiles(_currentPath);
      setState(() {
        _files = List<Map<String, dynamic>>.from(result['items'] ?? []);
      });
    } catch (e) {
      setState(() => _files = []);
    } finally {
      setState(() => _filesLoading = false);
    }
  }

  Future<void> _openFileItem(Map<String, dynamic> item) async {
    final fullPath = '$_currentPath/${item['name']}';
    if (item['is_dir'] == true) {
      setState(() {
        _currentPath = fullPath;
      });
      await _loadFiles();
    } else {
      // Open editor screen
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            filePath: fullPath,
            fileName: item['name'],
          ),
        ),
      );
      if (result == true) {
        _loadFiles();
      }
    }
  }

  void _createNewFile() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: const Text('Новый файл', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'index.html, script.py',
            hintStyle: TextStyle(color: VegaTheme.textSecondary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                final fullPath = '$_currentPath/$name';
                try {
                  await _client.writeFile(fullPath, '');
                  _loadFiles();
                  // Open editor directly
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditorScreen(filePath: fullPath, fileName: name),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка создания: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
              }
            },
            child: const Text('Создать', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // === TERMINAL LOGIC ===
  // ==========================================
  Future<void> _connectTerminal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8000';
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

      _termChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _termChannel!.stream.listen(
        (data) {
          setState(() {
            _termOutput.add(data.toString());
            _scrollTerminalToBottom();
          });
        },
        onError: (e) {
          setState(() {
            _termOutput.add('Ошибка WebSocket: $e');
            _termConnected = false;
          });
        },
        onDone: () {
          setState(() {
            _termOutput.add('WebSocket соединение закрыто.');
            _termConnected = false;
          });
        },
      );
      setState(() => _termConnected = true);
    } catch (e) {
      setState(() {
        _termOutput.add('Не удалось подключить терминал: $e');
        _termConnected = false;
      });
    }
  }

  void _scrollTerminalToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_termScrollCtrl.hasClients) {
        _termScrollCtrl.animateTo(
          _termScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendTerminalCommand() {
    final cmd = _termInputCtrl.text.trim();
    if (cmd.isEmpty || _termChannel == null) return;
    _termChannel!.sink.add(cmd);
    setState(() {
      _termOutput.add('\$ $cmd');
      _scrollTerminalToBottom();
    });
    _termInputCtrl.clear();
  }

  // ==========================================
  // === AI CODER CHAT LOGIC ===
  // ==========================================
  Future<void> _initIdeChat() async {
    final prefs = await SharedPreferences.getInstance();
    int? chatId = prefs.getInt('ide_chat_id');
    
    // Check if this chat actually exists in DB
    if (chatId != null) {
      final chats = await ChatHistory.getChats();
      final exists = chats.any((c) => c['id'] == chatId);
      if (!exists) {
        chatId = null;
      }
    }

    if (chatId == null) {
      // Create new chat specifically for IDE
      chatId = await ChatHistory.createChat('Кодер ИИ Workspace', projectId: 'ide');
      await prefs.setInt('ide_chat_id', chatId);
    }

    _ideChatId = chatId;
    _loadChatMessages();
  }

  Future<void> _loadChatMessages() async {
    if (_ideChatId == null) return;
    final msgs = await ChatHistory.getMessages(_ideChatId!);
    setState(() {
      _chatMessages = msgs;
    });
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _clearChat() async {
    if (_ideChatId == null) return;
    await ChatHistory.clearChatMessages(_ideChatId!);
    _loadChatMessages();
  }

  Future<void> _sendChatMessage() async {
    final text = _chatInputCtrl.text.trim();
    if (text.isEmpty && _attachedFiles.isEmpty) return;
    if (_chatLoading || _ideChatId == null) return;

    final attachedSnapshot = List<Map<String, dynamic>>.from(_attachedFiles);
    setState(() {
      _attachedFiles.clear();
      _chatLoading = true;
      _cancelStream = false;
    });

    _chatInputCtrl.clear();

    String msgContent = text;
    final List<Map<String, String>> files = [];

    String firstFilePath = '';
    String firstFileName = '';
    bool firstIsImage = false;

    if (attachedSnapshot.isNotEmpty) {
      final first = attachedSnapshot.first;
      firstFilePath = first['path'] ?? '';
      firstFileName = first['name'] ?? '';
      firstIsImage = first['isImage'] == true;
    }

    for (final f in attachedSnapshot) {
      final path = f['path'] as String;
      final name = f['name'] as String;
      final isImg = f['isImage'] == true;

      final bytes = await File(path).readAsBytes();
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

    final List<String> allFilePaths = attachedSnapshot
        .where((f) => f['isImage'] != true)
        .map((f) => f['path'] as String)
        .toList();
    final List<String> allFileNames = attachedSnapshot
        .where((f) => f['isImage'] != true)
        .map((f) => f['name'] as String)
        .toList();

    // Save user message to history
    await ChatHistory.addMessage(
      _ideChatId!, 'user', msgContent,
      filePath: firstFilePath, fileName: firstFileName, isImage: firstIsImage,
      filePaths: allFilePaths, fileNames: allFileNames,
    );

    setState(() {
      _chatMessages.add({
        'role': 'user',
        'content': msgContent,
        'filePath': firstFilePath,
        'fileName': firstFileName,
        'isImage': firstIsImage,
        'filePaths': allFilePaths,
        'fileNames': allFileNames,
      });
    });
    _scrollChatToBottom();

    // Prepare system instructions for IDE Agent
    const ideSystemPrompt = 
        "Ты — высококлассный Senior Full-Stack разработчик и искусственный интеллект-ассистент, встроенный в IDE среду Vega.\n"
        "Твоя задача — писать идеальный, рабочий, готовый к запуску код для проекта в папке /root/workspace.\n"
        "Ты можешь создавать/обновлять файлы, используя блоки:\n"
        "[WRITE_FILE:путь_к_файлу]\nсодержимое\n[/WRITE_FILE]\n\n"
        "А также запускать любые команды в терминале, выводя их в формате:\n"
        "<execute_command>команда</execute_command>\n"
        "Никогда не урезай код. Пиши его полностью.";

    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString('active_model') ?? 'google/gemini-2.5-flash';
    final provider = prefs.getString('active_provider') ?? 'openrouter';
    final geminiKey = prefs.getString('gemini_api_key') ?? '';

    // Convert messages for API call
    final messagesForApi = _chatMessages.map((m) => {
      'role': m['role'].toString(),
      'content': m['content'].toString(),
    }).toList();

    // Insert assistant message placeholder
    setState(() {
      _chatMessages.add({'role': 'assistant', 'content': ''});
    });

    final responseBuffer = StringBuffer();
    bool firstChunk = true;

    try {
      await _client.streamChat(
        messages: messagesForApi,
        model: model,
        provider: provider,
        geminiApiKey: geminiKey,
        systemPrompt: ideSystemPrompt,
        files: files.isEmpty ? null : files,
        onChunk: (chunk) {
          if (_cancelStream) return;
          if (firstChunk) {
            firstChunk = false;
          }
          responseBuffer.write(chunk);
          if (mounted) {
            setState(() {
              _chatMessages.last['content'] = responseBuffer.toString();
            });
            _scrollChatToBottom();
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _chatMessages.last['content'] = 'Ошибка: $err';
              _chatLoading = false;
            });
          }
        },
      );

      final finalResponse = responseBuffer.toString();
      if (finalResponse.isNotEmpty) {
        await ChatHistory.addMessage(_ideChatId!, 'assistant', finalResponse);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.last['content'] = 'Ошибка запроса: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _chatLoading = false;
        });
        _scrollChatToBottom();
      }
    }
  }

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
            const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 28),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.length > 20 ? name.substring(0, 20) + '…' : name,
                  style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Text('File', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ]),
        )).toList(),
      ),
    );
  }

  String _cleanMessageContent(String content) {
    String cleaned = content;
    cleaned = cleaned.replaceAll(RegExp(r'\[WRITE_FILE:.*?\][\s\S]*?\[/WRITE_FILE\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[WRITE_FILE:.*?\]'), '');
    cleaned = cleaned.replaceAll('[/WRITE_FILE]', '');
    cleaned = cleaned.replaceAll(RegExp(r'<execute_command>[\s\S]*?</execute_command>'), '');
    return cleaned.trim();
  }

  String? _extractCommand(String content) {
    final match = RegExp(r'<execute_command>([\s\S]*?)</execute_command>').firstMatch(content);
    return match?.group(1)?.trim();
  }

  Future<void> _onTerminalWidgetFinished(int msgIdx, String command, String output, bool success) async {
    // Send terminal execution results back to AI Coder
    if (_ideChatId == null) return;
    
    final resultMsg = "Команда `$command` завершена ${success ? 'успешно' : 'с ошибкой'}.\nВывод терминала:\n```\n$output\n```";
    
    await ChatHistory.addMessage(_ideChatId!, 'user', resultMsg);
    
    setState(() {
      _chatMessages.add({'role': 'user', 'content': resultMsg});
      _chatLoading = true;
    });
    _scrollChatToBottom();
    
    // Automatically trigger AI to respond to the terminal logs
    _sendChatMessageSilently();
  }

  Future<void> _sendChatMessageSilently() async {
    if (_ideChatId == null) return;
    
    const ideSystemPrompt = 
        "Ты — высококлассный Senior Full-Stack разработчик и искусственный интеллект-ассистент, встроенный в IDE среду Vega.\n"
        "Проанализируй вывод терминала, исправь ошибки, если они есть, и предложи следующий шаг.";

    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString('active_model') ?? 'google/gemini-2.5-flash';
    final provider = prefs.getString('active_provider') ?? 'openrouter';
    final geminiKey = prefs.getString('gemini_api_key') ?? '';

    final messagesForApi = _chatMessages.map((m) => {
      'role': m['role'].toString(),
      'content': m['content'].toString(),
    }).toList();

    setState(() {
      _chatMessages.add({'role': 'assistant', 'content': ''});
    });

    final responseBuffer = StringBuffer();

    try {
      await _client.streamChat(
        messages: messagesForApi,
        model: model,
        provider: provider,
        geminiApiKey: geminiKey,
        systemPrompt: ideSystemPrompt,
        onChunk: (chunk) {
          responseBuffer.write(chunk);
          if (mounted) {
            setState(() {
              _chatMessages.last['content'] = responseBuffer.toString();
            });
            _scrollChatToBottom();
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _chatMessages.last['content'] = 'Ошибка: $err';
              _chatLoading = false;
            });
          }
        },
      );

      final finalResponse = responseBuffer.toString();
      if (finalResponse.isNotEmpty) {
        await ChatHistory.addMessage(_ideChatId!, 'assistant', finalResponse);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.last['content'] = 'Ошибка: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _chatLoading = false;
        });
        _scrollChatToBottom();
      }
    }
  }

  // ==========================================
  // === UI BUILDERS ===
  // ==========================================
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
        title: const Text(
          'Рабочая область IDE',
          style: TextStyle(
            color: VegaTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: VegaTheme.accent,
          labelColor: VegaTheme.accent,
          unselectedLabelColor: VegaTheme.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Файлы', icon: Icon(Icons.folder_open_rounded, size: 20)),
            Tab(text: 'Кодер ИИ', icon: Icon(Icons.bolt_rounded, size: 20)),
            Tab(text: 'Терминал', icon: Icon(Icons.terminal_rounded, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── TAB 1: FILE EXPLORER ─────────────────────────────────────
          _buildFilesTab(),

          // ── TAB 2: AI CODER CHAT ─────────────────────────────────────
          _buildChatTab(),

          // ── TAB 3: TERMINAL CONSOLE ──────────────────────────────────
          _buildTerminalTab(),
        ],
      ),
    );
  }

  Widget _buildFilesTab() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewFile,
        backgroundColor: VegaTheme.accent,
        mini: true,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          // Breadcrumbs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: VegaTheme.surface,
            width: double.infinity,
            child: Row(
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 14, color: VegaTheme.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 12, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_currentPath != '/root/workspace')
                  GestureDetector(
                    onTap: () {
                      final parts = _currentPath.split('/');
                      parts.removeLast();
                      setState(() => _currentPath = parts.join('/'));
                      _loadFiles();
                    },
                    child: const Text('Назад', style: TextStyle(color: VegaTheme.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                  )
              ],
            ),
          ),
          
          Expanded(
            child: _filesLoading
                ? const Center(child: CircularProgressIndicator(color: VegaTheme.accent))
                : _files.isEmpty
                    ? const Center(child: Text('Папка пуста', style: TextStyle(color: VegaTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: _files.length,
                        itemBuilder: (ctx, i) {
                          final item = _files[i];
                          final isDir = item['is_dir'] == true;
                          return ListTile(
                            leading: Icon(
                              isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                              color: isDir ? VegaTheme.accent : VegaTheme.textSecondary,
                              size: 22,
                            ),
                            title: Text(
                              item['name'],
                              style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                            ),
                            trailing: isDir
                                ? const Icon(Icons.chevron_right_rounded, color: VegaTheme.textSecondary)
                                : Text(
                                    '${item['size']} B',
                                    style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
                                  ),
                            onTap: () => _openFileItem(item),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        // Top Action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: VegaTheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Изолированный контекст IDE', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 11)),
              TextButton.icon(
                onPressed: _clearChat,
                icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: Colors.redAccent),
                label: const Text('Очистить', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            ],
          ),
        ),

        // Chat messages list
        Expanded(
          child: _chatMessages.isEmpty
              ? const Center(
                  child: Text(
                    'Спроси кодера написать код,\nсобрать проект или запустить тесты.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: _chatMessages.length + (_chatLoading ? 1 : 0),
                  itemBuilder: (context, idx) {
                    if (_chatLoading && idx == _chatMessages.length) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _thinkingText,
                            style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ),
                      );
                    }
                    
                    final msg = _chatMessages[idx];
                    final isUser = msg['role'] == 'user';
                    final content = msg['content'] ?? '';
                    final cleanContent = _cleanMessageContent(content);
                    final cmd = _extractCommand(content);

                    return Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (msg['isImage'] == true || (msg['content'] as String? ?? '').contains('base64,'))
                           Container(
                             margin: const EdgeInsets.only(bottom: 8),
                             child: _buildImagesRow(msg),
                           ),
                        if (isUser && msg['isImage'] != true && (
                          (msg['filePaths'] as List<dynamic>?)?.isNotEmpty == true ||
                          ((msg['filePath'] ?? '') as String).isNotEmpty
                        ))
                           Padding(
                             padding: const EdgeInsets.only(bottom: 8),
                             child: _buildFileChips(msg),
                           ),
                        if (cleanContent.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isUser ? VegaTheme.userBubble : VegaTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: VegaTheme.border, width: 0.5),
                            ),
                            child: MarkdownBody(
                              data: cleanContent,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14, height: 1.5),
                                code: const TextStyle(
                                  color: VegaTheme.accent,
                                  backgroundColor: Colors.black26,
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        
                        // Inline terminal run request
                        if (cmd != null)
                          TerminalCommandWidget(
                            command: cmd,
                            onFinished: (output, success) {
                              _onTerminalWidgetFinished(idx, cmd, output, success);
                            },
                          ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
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
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 24),
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    att['name'] as String,
                                    style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 9),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
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

        // Chat Input box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: VegaTheme.surface,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_rounded, color: VegaTheme.textSecondary, size: 26),
                onPressed: _showAttachMenu,
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: VegaTheme.dark.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: VegaTheme.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _chatInputCtrl,
                    style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                    maxLines: 4,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: _isListening ? 'Слушаю...' : 'Спроси кодера...',
                      hintStyle: TextStyle(
                        color: _isListening ? VegaTheme.accent : VegaTheme.textSecondary,
                        fontSize: 13,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? VegaTheme.accent : VegaTheme.textSecondary,
                          size: 20,
                        ),
                        onPressed: _isListening ? _stopListening : _startListening,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    onSubmitted: (_) => _sendChatMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sendChatMessage,
                icon: const Icon(Icons.send_rounded, color: VegaTheme.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalTab() {
    return Column(
      children: [
        // Status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: VegaTheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Подключение к консоли Termux', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 11)),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _termConnected ? Colors.green : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _termConnected ? 'Подключен' : 'Отключен',
                    style: TextStyle(color: _termConnected ? Colors.green : Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  if (!_termConnected) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _connectTerminal,
                      child: const Text('Подключить', style: TextStyle(color: VegaTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Terminal Console output area
        Expanded(
          child: Container(
            color: const Color(0xFF020617), // Very dark slate terminal background
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              controller: _termScrollCtrl,
              itemCount: _termOutput.length,
              itemBuilder: (context, idx) {
                final line = _termOutput[idx];
                final isCommand = line.startsWith('\$');
                return SelectableText(
                  line,
                  style: TextStyle(
                    color: isCommand ? VegaTheme.accent : const Color(0xFFE2E8F0),
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                );
              },
            ),
          ),
        ),

        // Terminal input box
        Container(
          padding: const EdgeInsets.all(10),
          color: VegaTheme.surface,
          child: Row(
            children: [
              const Text('\$ ', style: TextStyle(color: VegaTheme.accent, fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold)),
              Expanded(
                child: TextField(
                  controller: _termInputCtrl,
                  style: const TextStyle(color: VegaTheme.textPrimary, fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Введите команду shell...',
                    hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  ),
                  onSubmitted: (_) => _sendTerminalCommand(),
                ),
              ),
              IconButton(
                onPressed: _sendTerminalCommand,
                icon: const Icon(Icons.send_rounded, color: VegaTheme.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
