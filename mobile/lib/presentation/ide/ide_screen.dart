import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // Required for ImageFilter
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

class _IdeScreenState extends State<IdeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _client = ApiClient();

  // === FILE EXPLORER STATE ===
  String _currentPath = '/root/workspace';
  List<Map<String, dynamic>> _files = [];
  bool _filesLoading = true;

  // === AI DEV CHAT STATE ===
  int? _ideChatId;
  List<Map<String, dynamic>> _chatMessages = [];
  List<Map<String, dynamic>> _ideChats = [];
  final _chatInputCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  bool _chatLoading = false;
  bool _cancelStream = false;
  final String _thinkingText = 'Кодер думает...';

  // === TERMINAL STATE ===
  final _termInputCtrl = TextEditingController();
  final _termScrollCtrl = ScrollController();
  final ValueNotifier<List<String>> _termOutputNotifier = ValueNotifier<List<String>>([]);
  WebSocketChannel? _termChannel;
  bool _termConnected = false;

  // === SPEECH & ATTACHMENTS STATE ===
  final speechToText.SpeechToText _speechToText = speechToText.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';
  final List<Map<String, dynamic>> _attachedFiles = [];
  bool _chatHasText = false;

  @override
  void initState() {
    super.initState();
    _chatInputCtrl.addListener(() {
      final text = _chatInputCtrl.text.trim();
      final hasText = text.isNotEmpty;
      if (hasText != _chatHasText) {
        setState(() {
          _chatHasText = hasText;
        });
      }
    });
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
    
    // Load directory files and IDE chat context
    await _loadFiles();
    await _initIdeChat();
    await _connectTerminal();
  }

  @override
  void dispose() {
    _chatInputCtrl.dispose();
    _chatScrollCtrl.dispose();
    _termInputCtrl.dispose();
    _termScrollCtrl.dispose();
    _termOutputNotifier.dispose();
    _termChannel?.sink.close();
    super.dispose();
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
          ListTile(
            leading: const Icon(Icons.photo_library, color: VegaTheme.accent),
            title: const Text('Фото', style: TextStyle(color: VegaTheme.textPrimary)),
            onTap: () { Navigator.pop(ctx); _pickImages(); },
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file, color: VegaTheme.accent),
            title: const Text('Файл', style: TextStyle(color: VegaTheme.textPrimary)),
            onTap: () { Navigator.pop(ctx); _pickFiles(); },
          ),
        ]),
      ),
    );
  }

  void _removeAttachment(int index) {
    setState(() => _attachedFiles.removeAt(index));
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
      // Close files drawer first
      Navigator.pop(context);
      
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
        title: const Text(
          'Новый файл',
          style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
                  // Close explorer drawer and open editor
                  if (mounted) {
                    Navigator.pop(context);
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

      _termChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _termChannel!.stream.listen(
        (data) {
          _termOutputNotifier.value = List.from(_termOutputNotifier.value)..add(data.toString());
          _scrollTerminalToBottom();
        },
        onError: (e) {
          _termOutputNotifier.value = List.from(_termOutputNotifier.value)..add('Ошибка WebSocket: $e');
          setState(() => _termConnected = false);
        },
        onDone: () {
          _termOutputNotifier.value = List.from(_termOutputNotifier.value)..add('WebSocket соединение закрыто.');
          setState(() => _termConnected = false);
        },
      );
      setState(() => _termConnected = true);
    } catch (e) {
      _termOutputNotifier.value = List.from(_termOutputNotifier.value)..add('Не удалось подключить терминал: $e');
      setState(() => _termConnected = false);
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
    _termOutputNotifier.value = List.from(_termOutputNotifier.value)..add('\$ $cmd');
    _termInputCtrl.clear();
    _scrollTerminalToBottom();
  }

  void _showTerminalBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.65,
            decoration: const BoxDecoration(
              color: Color(0xFF090D16), // Dark terminal background
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Bottom sheet drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                // Terminal Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.terminal, color: VegaTheme.accent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Консоль разработчика',
                            style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _termConnected ? Colors.green : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _termConnected ? 'Подключен' : 'Отключен',
                            style: TextStyle(
                              color: _termConnected ? Colors.green : Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 10),
                // Terminal logs output
                Expanded(
                  child: Container(
                    color: const Color(0xFF020617), // Deep black console
                    padding: const EdgeInsets.all(12),
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: _termOutputNotifier,
                      builder: (ctx, termLines, _) {
                        return ListView.builder(
                          controller: _termScrollCtrl,
                          itemCount: termLines.length,
                          itemBuilder: (ctx, i) {
                            final line = termLines[i];
                            final isCommand = line.startsWith('\$');
                            return SelectableText(
                              line,
                              style: TextStyle(
                                color: isCommand ? VegaTheme.accent : const Color(0xFFE2E8F0),
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.4,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                // Terminal Input
                Container(
                  color: VegaTheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            ),
          ),
        );
      },
    );
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
    await _loadChatMessages();
    await _loadIdeChats();
  }

  Future<void> _loadChatMessages() async {
    if (_ideChatId == null) return;
    final msgs = await ChatHistory.getMessages(_ideChatId!);
    setState(() {
      _chatMessages = msgs;
    });
    _scrollChatToBottom();
  }

  Future<void> _loadIdeChats() async {
    final allChats = await ChatHistory.getChats();
    setState(() {
      _ideChats = allChats.where((c) => c['projectId'] == 'ide').toList();
    });
  }

  Future<void> _createNewIdeChat() async {
    final title = 'Кодер ИИ ${DateTime.now().hour}:${DateTime.now().minute}';
    final chatId = await ChatHistory.createChat(title, projectId: 'ide');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ide_chat_id', chatId);
    
    setState(() {
      _ideChatId = chatId;
      _chatMessages.clear();
    });
    
    await _loadChatMessages();
    await _loadIdeChats();
    if (mounted) Navigator.pop(context); // Close endDrawer
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
    final provider = prefs.getString('provider') ?? 'openrouter';
    final savedModel = prefs.getString('model') ?? 'openrouter/auto';
    final model = prefs.getString('model_for_backend') ?? savedModel;
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
    if (_ideChatId == null) return;
    
    final resultMsg = "Команда `$command` завершена ${success ? 'успешно' : 'с ошибкой'}.\nВывод терминала:\n```\n$output\n```";
    
    await ChatHistory.addMessage(_ideChatId!, 'user', resultMsg);
    
    setState(() {
      _chatMessages.add({'role': 'user', 'content': resultMsg});
      _chatLoading = true;
    });
    _scrollChatToBottom();
    
    _sendChatMessageSilently();
  }

  Future<void> _sendChatMessageSilently() async {
    if (_ideChatId == null) return;
    
    const ideSystemPrompt = 
        "Ты — высококлассный Senior Full-Stack разработчик и искусственный интеллект-ассистент, встроенный в IDE среду Vega.\n"
        "Проанализируй вывод терминала, исправь ошибки, если они есть, и предложи следующий шаг.";

    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('provider') ?? 'openrouter';
    final savedModel = prefs.getString('model') ?? 'openrouter/auto';
    final model = prefs.getString('model_for_backend') ?? savedModel;
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
  Widget _buildWelcomeScreen() {
    final suggestions = [
      {'icon': '💻', 'text': 'Создать файл index.html', 'prompt': 'Создай простой файл index.html с базовой разметкой'},
      {'icon': '🛠️', 'text': 'Установить httpx', 'prompt': 'Установи библиотеку httpx в проект'},
      {'icon': '🔍', 'text': 'Проверить ошибки', 'prompt': 'Проверь файлы проекта в /root/workspace на ошибки'},
      {'icon': '🚀', 'text': 'Запустить тесты', 'prompt': 'Запусти сборку проекта или тесты'}
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.7, -0.4),
                radius: 1.2,
                colors: [VegaTheme.accent.withOpacity(0.08), const Color(0x00000000)],
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
        Align(
          alignment: const Alignment(0, -0.15),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo anim scale
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1.0),
                  duration: const Duration(milliseconds: 1500),
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
                const SizedBox(height: 18),
                const Text(
                  'Режим IDE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: VegaTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ваша автономная среда разработки и ИИ-ассистент',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: VegaTheme.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                // Suggestions grid
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
                      _chatInputCtrl.text = s['prompt']!;
                      _chatInputCtrl.selection = TextSelection.fromPosition(
                        TextPosition(offset: _chatInputCtrl.text.length),
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
                          Flexible(
                            child: Text(
                              s['text']!, 
                              style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13), 
                              overflow: TextOverflow.ellipsis
                            ),
                          ),
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

  Widget _buildFilesDrawer() {
    return Drawer(
      backgroundColor: VegaTheme.dark,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Проводник файлов',
                    style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: _createNewFile,
                    icon: const Icon(Icons.add, color: VegaTheme.accent),
                    tooltip: 'Создать файл',
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            // Path breadcrumbs
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
                        _loadFiles();
                      },
                      child: const Text('Назад', style: TextStyle(color: VegaTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                ],
              ),
            ),
            // Files List
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
                                size: 20,
                              ),
                              title: Text(
                                item['name'],
                                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13),
                              ),
                              trailing: isDir
                                  ? const Icon(Icons.chevron_right_rounded, color: VegaTheme.textSecondary, size: 18)
                                  : Text(
                                      '${item['size']} B',
                                      style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 10),
                                    ),
                              onTap: () => _openFileItem(item),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsDrawer() {
    return Drawer(
      backgroundColor: VegaTheme.dark,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Сессии Кодера IDE',
                    style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: _createNewIdeChat,
                    icon: const Icon(Icons.add_comment_rounded, color: VegaTheme.accent),
                    tooltip: 'Новый чат',
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            // Actions panel: Clear current chat
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              title: const Text('Очистить историю текущего чата', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
              onTap: () async {
                await _clearChat();
                if (mounted) Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white10, height: 1),
            // List of chats
            Expanded(
              child: _ideChats.isEmpty
                  ? const Center(child: Text('Нет активных сессий', style: TextStyle(color: VegaTheme.textSecondary)))
                  : ListView.builder(
                      itemCount: _ideChats.length,
                      itemBuilder: (ctx, i) {
                        final chat = _ideChats[i];
                        final isSelected = chat['id'] == _ideChatId;
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: VegaTheme.surface,
                          leading: Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: isSelected ? VegaTheme.accent : VegaTheme.textSecondary,
                            size: 20,
                          ),
                          title: Text(
                            chat['title'] ?? 'Без названия',
                            style: TextStyle(
                              color: isSelected ? VegaTheme.accent : VegaTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                            onPressed: () async {
                              final chatId = chat['id'] as int;
                              await ChatHistory.deleteChat(chatId);
                              if (_ideChatId == chatId) {
                                _ideChatId = null;
                                await _initIdeChat();
                              } else {
                                await _loadIdeChats();
                              }
                            },
                          ),
                          onTap: () {
                            setState(() {
                              _ideChatId = chat['id'];
                              _loadChatMessages();
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: VegaTheme.dark,
      drawer: _buildFilesDrawer(),
      endDrawer: _buildChatsDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            // Files drawer open button
            IconButton(
              icon: const Icon(Icons.folder_open_rounded, color: VegaTheme.accent, size: 24),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Проводник файлов',
            ),
            // Terminal dialog open button
            IconButton(
              icon: const Icon(Icons.terminal_rounded, color: VegaTheme.accent, size: 24),
              onPressed: () => _showTerminalBottomSheet(context),
              tooltip: 'Консоль',
            ),
            const SizedBox(width: 8),
            const Text(
              'Режим IDE',
              style: TextStyle(
                color: VegaTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.forum_outlined, color: VegaTheme.accent, size: 24),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Чаты IDE',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Chat messages list / Welcome screen
          Positioned.fill(
            child: Padding(
              // Safe area padding for the glassmorphic transparent bottom bar
              padding: const EdgeInsets.only(bottom: 85),
              child: (_chatMessages.isEmpty && !_chatHasText)
                  ? _buildWelcomeScreen()
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
          ),

          // Glassmorphic Input Panel positioned at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_attachedFiles.isNotEmpty)
                  Container(
                    height: 80,
                    color: VegaTheme.surface.withOpacity(0.9),
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

                // Glassmorphic Input Bar Container with blur filter
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: VegaTheme.dark.withOpacity(0.55),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add, color: VegaTheme.textSecondary, size: 26),
                              onPressed: _showAttachMenu,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _chatInputCtrl,
                                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                                maxLines: 4,
                                minLines: 1,
                                textAlignVertical: TextAlignVertical.center, // Centers vertically
                                decoration: InputDecoration(
                                  hintText: _isListening ? 'Слушаю...' : 'Спроси кодера...',
                                  hintStyle: TextStyle(
                                    color: _isListening ? VegaTheme.accent : VegaTheme.textSecondary,
                                    fontSize: 13.5,
                                  ),
                                  filled: true,
                                  fillColor: VegaTheme.surface,
                                  // Outline border to match the clean default chat design
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  // Padding aligned perfectly to keep text centered
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                            const SizedBox(width: 8),
                            // Circular Send Button with upward arrow, dynamically disabled/greyed out
                            Builder(
                              builder: (context) {
                                final hasContent = _chatHasText || _attachedFiles.isNotEmpty;
                                return GestureDetector(
                                  onTap: hasContent ? _sendChatMessage : null,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasContent ? VegaTheme.accent : VegaTheme.surface,
                                    ),
                                    child: Icon(
                                      Icons.arrow_upward_rounded, // Upward arrow
                                      color: hasContent ? Colors.white : VegaTheme.textSecondary,
                                      size: 22,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
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
