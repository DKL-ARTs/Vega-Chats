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
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:speech_to_text/speech_to_text.dart' as speechToText;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../ide/ide_screen.dart';
import 'widgets/image_viewer_dialog.dart';
import 'widgets/shimmer_thinking_indicator.dart';

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
  String _provider = 'openrouter';
  String _geminiApiKey = '';
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
  List<Map<String, dynamic>> _projects = [];
  String _activeProjectId = 'default';
  String _activeProjectPrompt = '';

  // Speech to Text variables
  final speechToText.SpeechToText _speechToText = speechToText.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';
  String _speechLocale = 'ru_RU';

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
      final typing = _controller.text.trim().isNotEmpty;
      if (typing != _isTyping) setState(() => _isTyping = typing);
    });
  }

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
              _controller.text = _lastWords;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            }
          });
        },
        listenMode: speechToText.ListenMode.dictation,
        pauseFor: const Duration(seconds: 5),
        localeId: _speechLocale == 'auto' ? null : _speechLocale,
      );
    }
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload settings (model etc.) every time this screen becomes active
    // e.g. after returning from Settings page
    _loadSettings();
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 4.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: VegaTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_isListening) {
      _speechToText.stop();
    }
    _controller.dispose();
    _searchController.dispose();
    _thinkingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projectsJson = prefs.getString('projects_list');
    
    List<Map<String, dynamic>> loadedProjects = [];
    if (projectsJson != null) {
      try {
        final decoded = jsonDecode(projectsJson) as List<dynamic>;
        loadedProjects = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint('Error decoding projects: $e');
      }
    }
    
    if (loadedProjects.isEmpty) {
      loadedProjects = [
        {
          'id': 'default',
          'name': 'Общий помощник',
          'prompt': 'Ты — полезный, дружелюбный и умный ИИ-ассистент.'
        },
        {
          'id': 'flutter',
          'name': 'Flutter-разработчик',
          'prompt': 'Ты — эксперт по разработке мобильных приложений на Flutter и Dart. Пиши чистый, оптимизированный код, следуй правилам чистой архитектуры.'
        },
        {
          'id': 'python',
          'name': 'Python-разработчик',
          'prompt': 'Ты — опытный Senior Python разработчик. Пиши чистый, питоничный код (PEP 8), помогай писать автоматизацию и веб-приложения на FastAPI/Django.'
        },
        {
          'id': 'qa',
          'name': 'Тестировщик кода',
          'prompt': 'Ты — QA инженер. Помогай писать Unit-тесты, искать логические ошибки и граничные случаи в предоставленном коде.'
        }
      ];
      await prefs.setString('projects_list', jsonEncode(loadedProjects));
    }

    final activeId = prefs.getString('active_project_id') ?? 'default';
    final activeProj = loadedProjects.firstWhere((p) => p['id'] == activeId, orElse: () => loadedProjects.first);

    setState(() {
      _projects = loadedProjects;
      _activeProjectId = activeProj['id'] ?? 'default';
      _activeProjectPrompt = activeProj['prompt'] ?? '';
    });
  }

  Future<void> _selectProject(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_project_id', id);
    final activeProj = _projects.firstWhere((p) => p['id'] == id, orElse: () => _projects.first);
    setState(() {
      _activeProjectId = id;
      _activeProjectPrompt = activeProj['prompt'] ?? '';
    });
  }

  Future<void> _createProject(String name, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final newProj = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'prompt': prompt,
    };
    setState(() {
      _projects.add(newProj);
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    await _selectProject(newProj['id']!);
  }

  Future<void> _deleteProject(String id) async {
    if (id == 'default') return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _projects.removeWhere((p) => p['id'] == id);
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    if (_activeProjectId == id) {
      await _selectProject('default');
    }
  }

  Future<void> _editProject(String id, String name, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final index = _projects.indexWhere((p) => p['id'] == id);
      if (index != -1) {
        _projects[index] = {
          'id': id,
          'name': name,
          'prompt': prompt,
        };
      }
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    if (_activeProjectId == id) {
      setState(() {
        _activeProjectPrompt = prompt;
      });
    }
  }

  void _showCreateProjectDialog({Map<String, dynamic>? projectToEdit}) {
    final isEdit = projectToEdit != null;
    final nameCtrl = TextEditingController(text: isEdit ? projectToEdit['name'] : '');
    final promptCtrl = TextEditingController(text: isEdit ? projectToEdit['prompt'] : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: Text(isEdit ? 'Редактировать проект' : 'Создать проект', style: const TextStyle(color: VegaTheme.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Название проекта',
                  labelStyle: TextStyle(color: VegaTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: promptCtrl,
                maxLines: 4,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Системный промпт / Инструкции',
                  labelStyle: TextStyle(color: VegaTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final prompt = promptCtrl.text.trim();
              if (name.isNotEmpty) {
                if (isEdit) {
                  _editProject(projectToEdit['id']!, name, prompt);
                } else {
                  _createProject(name, prompt);
                }
                Navigator.pop(ctx);
              }
            },
            child: Text(isEdit ? 'Сохранить' : 'Создать', style: const TextStyle(color: VegaTheme.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
    if (baseUrl.contains('vega-chat-production') && !baseUrl.contains('vega-chats-production')) {
      baseUrl = 'https://vega-chats-production.up.railway.app';
      await prefs.setString('base_url', baseUrl);
    }
    // Read the resolved model/provider saved by settings screen
    final savedModel = prefs.getString('model') ?? 'openrouter/auto';
    final provider = prefs.getString('provider') ?? 'openrouter';
    final modelForBackend = prefs.getString('model_for_backend') ?? savedModel;
    setState(() {
      _provider = provider;
      _model = modelForBackend;
      _geminiApiKey = prefs.getString('gemini_api_key') ?? '';
      _client.apiKey = prefs.getString('api_key') ?? '';
      _client.baseUrl = baseUrl;
      _speechLocale = prefs.getString('speech_locale') ?? 'ru_RU';
    });
    await _loadProjects();
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

  String get _thinkingText => 'Думаю' + '.' * _thinkingDots;

  Future<void> _handleLinkTap(String url) async {
    try {
      final fullUrl = (url.startsWith('/') && !url.startsWith('//')) ? '${_client.baseUrl}$url' : url;
      await launchUrl(Uri.parse(fullUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
        );
      }
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
        projectId: _activeProjectId,
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
        provider: _provider,
        geminiApiKey: _geminiApiKey,
        systemPrompt: _activeProjectPrompt,
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
        _autoUpdateChatTitle(_currentChatId!);
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
        provider: _provider,
        geminiApiKey: _geminiApiKey,
        systemPrompt: _activeProjectPrompt,
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
        _autoUpdateChatTitle(_currentChatId!);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: VegaTheme.accent),
              title: const Text('Редактировать', style: TextStyle(color: VegaTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _editMessage(index, message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: VegaTheme.accent),
              title: const Text('Копировать', style: TextStyle(color: VegaTheme.textPrimary)),
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

  void _editMessage(int index, Map<String, dynamic> message) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => EditMessageDialog(
        initialText: message['content'] ?? '',
        initialFilePaths: List<String>.from(message['filePaths'] ?? []),
        initialFileNames: List<String>.from(message['fileNames'] ?? []),
        initialFilePath: message['filePath'] ?? '',
        initialFileName: message['fileName'] ?? '',
        initialIsImage: message['isImage'] == true,
        copyFileToAppDir: _copyFileToAppDir,
      ),
    );

    if (result != null) {
      final newText = result['text'] as String;
      final attachments = result['attachments'] as List<Map<String, dynamic>>;
      await _submitEditedMessage(index, newText, attachments);
    }
  }

  Future<void> _submitEditedMessage(int userIndex, String newText, List<Map<String, dynamic>> attachments) async {
    if (_loading) return;

    int assistantIndex = userIndex + 1;
    while (assistantIndex < _messages.length && _messages[assistantIndex]['role'] != 'assistant') {
      assistantIndex++;
    }
    if (assistantIndex >= _messages.length) {
      assistantIndex = _messages.length - 1;
    }

    final prefix = _messages.sublist(0, userIndex);
    final targetUser = Map<String, dynamic>.from(_messages[userIndex]);
    targetUser['content'] = newText;
    final allFilePaths = attachments.map((att) => att['path'] as String).toList();
    final allFileNames = attachments.map((att) => att['name'] as String).toList();
    final firstIsImage = attachments.isNotEmpty && attachments.first['isImage'] == true;
    final firstFilePath = attachments.isNotEmpty ? attachments.first['path'] as String : '';
    final firstFileName = attachments.isNotEmpty ? attachments.first['name'] as String : '';

    targetUser['filePaths'] = allFilePaths;
    targetUser['fileNames'] = allFileNames;
    targetUser['filePath'] = firstFilePath;
    targetUser['fileName'] = firstFileName;
    targetUser['isImage'] = firstIsImage;

    final suffix = assistantIndex + 1 < _messages.length 
        ? _messages.sublist(assistantIndex + 1) 
        : <Map<String, dynamic>>[];

    final newAssistant = {'role': 'assistant', 'content': ''};

    setState(() {
      _messages.clear();
      _messages.addAll(prefix);
      _messages.add(targetUser);
      _messages.add(newAssistant);
      _messages.addAll(suffix);
      _loading = true;
    });

    final newAssistantIndexInState = prefix.length + 1;

    _startThinking();
    try {
      final msgs = _messages.sublist(0, newAssistantIndexInState).map((m) =>
        {'role': m['role'].toString(), 'content': m['content'].toString()}).toList();
        
      List<Map<String, String>>? regenFiles;
      final nonImageAtts = attachments.where((att) => att['isImage'] != true).toList();
      if (nonImageAtts.isNotEmpty) {
        regenFiles = [];
        for (final att in nonImageAtts) {
          try {
            final bytes = await File(att['path'] as String).readAsBytes();
            regenFiles.add({'name': att['name'] as String, 'content': base64Encode(bytes)});
          } catch (_) {}
        }
        if (regenFiles.isEmpty) regenFiles = null;
      }

      final imageAtts = attachments.where((att) => att['isImage'] == true).toList();
      String updatedMsgContent = newText;
      for (final att in imageAtts) {
        try {
          final bytes = await File(att['path'] as String).readAsBytes();
          final ext = (att['name'] as String).split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : (ext == 'gif' ? 'image/gif' : 'image/jpeg');
          final b64 = base64Encode(bytes);
          updatedMsgContent = updatedMsgContent.isEmpty
              ? '![image](data:$mime;base64,$b64)'
              : '$updatedMsgContent\n\n![image](data:$mime;base64,$b64)';
        } catch (_) {}
      }

      msgs.last['content'] = updatedMsgContent;

      final responseBuffer = StringBuffer();
      bool firstChunk = true;
      await _client.streamChat(
        messages: msgs,
        model: _model,
        provider: _provider,
        geminiApiKey: _geminiApiKey,
        systemPrompt: _activeProjectPrompt,
        files: regenFiles,
        onChunk: (chunk) {
          if (firstChunk) {
            _stopThinking();
            firstChunk = false;
          }
          responseBuffer.write(chunk);
          if (mounted) {
            setState(() {
              _messages[newAssistantIndexInState]['content'] = responseBuffer.toString();
            });
          }
        },
        onError: (error) {
          _stopThinking();
          if (mounted) {
            setState(() {
              _messages[newAssistantIndexInState]['content'] = 'Error: $error';
            });
          }
        },
      );
      _stopThinking();
      
      if (_currentChatId != null) {
        await ChatHistory.overwriteMessages(_currentChatId!, _messages);
      }
    } catch (e) {
      if (mounted) setState(() { _messages[newAssistantIndexInState]["content"] = "Error: $e"; });
    } finally {
      if (mounted) setState(() { _loading = false; _stopThinking(); });
    }
  }

  Future<void> _deleteChat(int chatId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: Text('Удалить чат?', style: TextStyle(color: VegaTheme.textPrimary)),
        content: Text('Это действие нельзя отменить.', style: TextStyle(color: VegaTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Удалить', style: TextStyle(color: Colors.red)),
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

  Future<void> _autoUpdateChatTitle(int chatId) async {
    try {
      final messages = await ChatHistory.getMessages(chatId);
      if (messages.isEmpty) return;
      
      final len = messages.length;
      if (len != 2 && len % 10 != 0) return;
      
      final List<Map<String, dynamic>> summaryMessages = [
        {
          'role': 'system',
          'content': 'Вы — полезный ассистент. Твоя единственная задача — придумать ОЧЕНЬ короткое и емкое название (2-4 слова) на русском языке для диалога по его началу или продолжению. Ответь ТОЛЬКО названием, БЕЗ кавычек, БЕЗ знаков препинания на конце и БЕЗ пояснений.',
        }
      ];
      
      final startIdx = len > 10 ? len - 10 : 0;
      for (int i = startIdx; i < len; i++) {
        final m = messages[i];
        final content = m['content'] as String? ?? '';
        final cleanContent = content.replaceAll(RegExp(r'```[\s\S]*?```'), '[код]');
        summaryMessages.add({
          'role': m['role'] ?? 'user',
          'content': cleanContent.length > 200 ? cleanContent.substring(0, 200) + '...' : cleanContent,
        });
      }
      
      final titleResponse = await _client.chat(
        messages: summaryMessages,
        model: _model,
      );
      
      final cleanTitle = titleResponse.trim().replaceAll('"', '').replaceAll("'", '').replaceAll('.', '');
      if (cleanTitle.isNotEmpty && cleanTitle.length < 50 && !cleanTitle.startsWith('Error:')) {
        await ChatHistory.updateChatTitle(chatId, cleanTitle);
        await _loadChats();
      }
    } catch (e) {
      print('Auto-title update failed: $e');
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

  IconData _getIconData(String name) {
    switch (name) {
      case 'folder': return Icons.folder_rounded;
      case 'money': return Icons.monetization_on_rounded;
      case 'book': return Icons.menu_book_rounded;
      case 'school': return Icons.school_rounded;
      case 'edit': return Icons.edit_rounded;
      case 'code': return Icons.code_rounded;
      case 'terminal': return Icons.terminal_rounded;
      case 'music': return Icons.music_note_rounded;
      case 'cake': return Icons.cake_rounded;
      case 'palette': return Icons.palette_rounded;
      case 'spa': return Icons.spa_rounded;
      case 'work': return Icons.work_rounded;
      case 'chart': return Icons.bar_chart_rounded;
      case 'fitness': return Icons.fitness_center_rounded;
      case 'calendar': return Icons.calendar_today_rounded;
      case 'balance': return Icons.balance_rounded;
      case 'flight': return Icons.flight_rounded;
      case 'language': return Icons.language_rounded;
      case 'pets': return Icons.pets_rounded;
      case 'science': return Icons.science_rounded;
      case 'psychology': return Icons.psychology_rounded;
      case 'flower': return Icons.local_florist_rounded;
      case 'wrench': return Icons.build_rounded;
      case 'heart': return Icons.favorite_rounded;
      case 'bug': return Icons.bug_report_rounded;
      default: return Icons.folder_open_rounded;
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Доброй ночи 🌙';
    if (hour < 12) return 'Доброе утро ☀️';
    if (hour < 18) return 'Добрый день 👋';
    return 'Добрый вечер ✨';
  }

  Color _parseHexColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  List<Map<String, String>> _getSuggestions(Map<String, dynamic> project) {
    final rawSuggestions = project['suggestions'];
    
    if (rawSuggestions == null || (rawSuggestions is List && rawSuggestions.isEmpty)) {
      return [
        {'icon': '💻', 'text': 'Написать код', 'prompt': 'Напиши код для '},
        {'icon': '📚', 'text': 'Объяснить тему', 'prompt': 'Объясни мне простыми словами что такое '},
        {'icon': '✍️', 'text': 'Написать текст', 'prompt': 'Напиши текст на тему '},
        {'icon': '💡', 'text': 'Придумать идею', 'prompt': 'Предложи креативные идеи для '}
      ];
    }

    if (rawSuggestions is List) {
      if (rawSuggestions.isEmpty) return [];
      final first = rawSuggestions.first;
      if (first is Map) {
        return rawSuggestions.map((e) {
          final m = Map<dynamic, dynamic>.from(e);
          return {
            'icon': (m['icon'] ?? '💡').toString(),
            'text': (m['text'] ?? '').toString(),
            'prompt': (m['prompt'] ?? '').toString(),
          };
        }).toList();
      } else {
        final list = List<String>.from(rawSuggestions.map((e) => e.toString()));
        final emojis = ['💡', '✍️', '❓', '🔍', '🚀', '🛠️', '📚', '💻'];
        return List.generate(list.length, (idx) {
          final text = list[idx];
          String prompt = '$text ';
          if (text.toLowerCase().contains('код')) prompt = 'Напиши код для ';
          if (text.toLowerCase().contains('объясн')) prompt = 'Объясни мне простыми словами что такое ';
          if (text.toLowerCase().contains('текст')) prompt = 'Напиши текст на тему ';
          if (text.toLowerCase().contains('иде')) prompt = 'Предложи креативные идеи для ';
          return {
            'icon': emojis[idx % emojis.length],
            'text': text,
            'prompt': prompt,
          };
        });
      }
    }

    return [];
  }

  Widget _buildWelcomeScreen() {
    final activeProj = _projects.firstWhere(
      (p) => p['id'] == _activeProjectId, 
      orElse: () => {
        'id': 'default',
        'name': 'Общий помощник',
        'description': 'Универсальный ИИ-помощник без специфичных системных инструкций.',
        'iconColor': '#7C4DFF',
        'suggestions': ['Написать код', 'Объяснить тему', 'Написать текст', 'Придумать идею']
      }
    );
    final projName = activeProj['name'] ?? 'Общий помощник';
    final projDesc = activeProj['description'] ?? '';
    final suggestions = _getSuggestions(activeProj);
    final isDefault = _activeProjectId == 'default';
    final projColor = _parseHexColor(activeProj['iconColor'] ?? '#7C4DFF');

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.7, -0.4),
                radius: 1.2,
                colors: [projColor.withOpacity(0.08), const Color(0x00000000)],
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
        Align(
          alignment: const Alignment(0, -0.15),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                              color: projColor.withOpacity(0.25 * value),
                              blurRadius: 28 * value,
                              spreadRadius: 4 * value,
                            ),
                          ],
                        ),
                        child: isDefault
                            ? ClipOval(
                                child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                              )
                            : CircleAvatar(
                                backgroundColor: projColor,
                                child: Icon(
                                  _getIconData(activeProj['iconName'] ?? 'folder'),
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (!_isTyping) ...[
                  Text(
                    isDefault ? _getGreeting() : projName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: VegaTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isDefault ? 'Пишу код, ищу ошибки, отвечаю\nна вопросы и генерирую идеи' : projDesc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: VegaTheme.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
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
          child: GestureDetector(
            onTap: () => showImageViewer(context, base64Data: b64),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(b64),
                width: 250, fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: VegaTheme.textSecondary),
              ),
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
              return GestureDetector(
                onTap: () => showImageViewer(context, base64Data: b64),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(b64),
                    width: 160, height: 180, fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: VegaTheme.textSecondary),
                  ),
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
      return GestureDetector(
        onTap: () => showImageViewer(context, imagePath: filePath, title: p.basename(filePath)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(filePath), width: 250, fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: VegaTheme.textSecondary)),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Parses list of generated files from assistant content.
  List<Map<String, String>> _extractGeneratedFiles(String content) {
    final List<Map<String, String>> list = [];
    final Set<String> seenPaths = {};
    final pattern = RegExp(r'\[([^\]]*?)\]\(/api/files/download\?path=([^)]+)\)');
    for (final match in pattern.allMatches(content)) {
      final name = match.group(1) ?? 'file';
      final path = match.group(2) ?? '';
      if (path.isNotEmpty && !seenPaths.contains(path)) {
        seenPaths.add(path);
        String cleanName = name.replaceAll('Скачать ', '').replaceAll('файл ', '').replaceAll('`', '').trim();
        list.add({'name': cleanName, 'path': path});
      }
    }
    return list;
  }

  /// Cleans the raw file download markdown block from assistant message content.
  String _cleanMessageContent(String content) {
    String cleaned = content;
    // Strip write file tags and their contents completely
    cleaned = cleaned.replaceAll(RegExp(r'\[WRITE_FILE:.*?\][\s\S]*?\[/WRITE_FILE\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[WRITE_FILE:.*?\]'), '');
    cleaned = cleaned.replaceAll('[/WRITE_FILE]', '');
    cleaned = cleaned.replaceAll(RegExp(r'WRITE_FILE:.*?\]'), '');
    // Strip execute command tags
    cleaned = cleaned.replaceAll(RegExp(r'<execute_command>[\s\S]*?</execute_command>'), '');
    // Strip download links
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*?\]\(/api/files/download\?path=[^)]+\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'Вы можете\s*$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'Вы можете\s*\n'), '');
    cleaned = cleaned.replaceAll(RegExp(r'### 💾 Создан файл.*?\n'), '');
    cleaned = cleaned.replaceAll(RegExp(r'### 💾 Создан файл.*?$'), '');
    return cleaned.trim();
  }

  String? _extractCommand(String content) {
    final match = RegExp(r'<execute_command>([\s\S]*?)</execute_command>').firstMatch(content);
    return match?.group(1)?.trim();
  }

  String _getWsUrl() {
    final httpUrl = _client.baseUrl;
    final uri = Uri.parse(httpUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '$wsScheme://$host$portPart/ws/terminal';
  }

  Future<void> _runTerminalCommand(int msgIndex, String command) async {
    final msg = _messages[msgIndex];
    setState(() {
      msg['terminalStatus'] = 'running';
      msg['terminalOutput'] = 'Запуск команды...\n';
    });

    try {
      final wsUrl = _getWsUrl();
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      channel.sink.add(command);
      
      await for (final data in channel.stream) {
        if (!mounted) break;
        setState(() {
          msg['terminalOutput'] = (msg['terminalOutput'] ?? '') + data.toString();
        });
      }
      
      if (mounted) {
        setState(() {
          msg['terminalStatus'] = 'done';
        });
        
        final finalOutput = msg['terminalOutput'] ?? '';
        final cleanOutput = finalOutput.replaceAll('Запуск команды...\n', '');
        await _sendSystemMessage(
          "Команда `$command` выполнена.\nВывод терминала:\n```\n$cleanOutput\n```"
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          msg['terminalStatus'] = 'error';
          msg['terminalOutput'] = (msg['terminalOutput'] ?? '') + '\nОшибка: $e\n';
        });
      }
    }
  }

  Future<void> _sendSystemMessage(String content) async {
    if (_loading || _currentChatId == null) return;
    
    await ChatHistory.addMessage(_currentChatId!, 'user', content);
    await _loadChats();
    
    setState(() {
      _messages.add({'role': 'user', 'content': content});
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
        provider: _provider,
        geminiApiKey: _geminiApiKey,
        systemPrompt: _activeProjectPrompt,
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
      if (finalResponse.isNotEmpty) {
        await ChatHistory.addMessage(_currentChatId!, 'assistant', finalResponse);
      }
    } catch (e) {
      _stopThinking();
    } finally {
      if (mounted) setState(() { _loading = false; _cancelStream = false; });
    }
  }

  Widget _buildTerminalCard(int msgIndex, String command) {
    final msg = _messages[msgIndex];
    final status = msg['terminalStatus'] ?? 'idle';
    final output = msg['terminalOutput'] ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: VegaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'running' 
              ? VegaTheme.accent 
              : (status == 'done' ? Colors.green.withOpacity(0.5) : VegaTheme.border),
          width: status == 'idle' ? 0.5 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_rounded, 
                  color: status == 'running' 
                      ? VegaTheme.accent 
                      : (status == 'done' ? Colors.greenAccent : VegaTheme.textSecondary),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status == 'running'
                        ? 'Выполнение команды...'
                        : (status == 'done' ? 'Команда выполнена успешно' : 'Запрос на выполнение команды'),
                    style: const TextStyle(
                      color: VegaTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (status == 'running')
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: VegaTheme.accent),
                  )
                else if (status == 'done')
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: VegaTheme.dark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              command,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
          ),
          if (status != 'idle') ...[
            const SizedBox(height: 10),
            Container(
              height: 150,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  output,
                  style: const TextStyle(
                    color: Colors.lightGreenAccent,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (status == 'idle')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        msg['terminalStatus'] = 'declined';
                      });
                    },
                    child: const Text('Отклонить', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _runTerminalCommand(msgIndex, command),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VegaTheme.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                    label: const Text('Запустить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            )
          else if (status == 'declined')
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'Запуск команды отклонен пользователем.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
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

  /// Downloads the generated file (triggers native system browser download manager to bypass Scoped Storage).
  Future<void> _downloadGeneratedFile(String filePath, String fileName) async {
    setState(() {
      _fileDownloadStatus[filePath] = 'loading';
    });

    try {
      final downloadUrl = '/api/files/download?path=$filePath';
      final fullUrl = '${_client.baseUrl}$downloadUrl';
      final uri = Uri.parse(fullUrl);

      // Open the URL in the system browser to trigger a native download to the user's Downloads folder
      await launchUrl(uri, mode: LaunchMode.externalApplication);

      // Show success animation state briefly
      setState(() {
        _fileDownloadStatus[filePath] = 'success';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _fileDownloadStatus[filePath] = 'idle';
          });
        }
      });
    } catch (e) {
      setState(() {
        _fileDownloadStatus[filePath] = 'idle';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка запуска загрузки: $e')),
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
                      'Сгенерированный файл',
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
        width: MediaQuery.of(context).size.width * 0.65,
        backgroundColor: VegaTheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Vega Chat', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
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
                      hintText: 'Поиск чатов...',
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
                child: Builder(builder: (ctx) {
                  final projectChats = _chats.where((c) {
                    final pId = c['projectId'];
                    return pId == null || pId == 'default' || pId == '';
                  }).toList();

                  if (projectChats.isEmpty) {
                    return const Center(child: Text('Нет чатов', style: TextStyle(color: VegaTheme.textSecondary)));
                  }

                  final filtered = _searchQuery.isEmpty
                      ? projectChats
                      : projectChats.where((c) => (c['title'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('Ничего не найдено', style: TextStyle(color: VegaTheme.textSecondary)));
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final chat = filtered[i];
                          final isActive = chat['id'] == _currentChatId;
                          return ListTile(
                            selected: isActive,
                            selectedTileColor: VegaTheme.card,
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
                                    chat['title'] ?? 'Без названия',
                                    style: TextStyle(color: isActive ? VegaTheme.accent : VegaTheme.textPrimary, fontSize: 14),
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
                                  _renameChat(chat['id'], chat['title'] ?? 'Без названия');
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
                            onTap: () => _openChat(chat['id']),
                          );
                        },
                      );
                      }),
              ),
              ListTile(
                leading: const Icon(Icons.workspaces_outline, color: VegaTheme.accent),
                title: const Text('Проекты', style: TextStyle(color: VegaTheme.textPrimary)),
                onTap: () async {
                  _scaffoldKey.currentState?.closeDrawer();
                  final reloaded = await context.push('/projects');
                  if (reloaded == true) {
                    _startNewChat();
                    _loadSettings();
                    _loadChats();
                  } else if (reloaded is Map) {
                    final pId = reloaded['projectId'] as String;
                    final cId = reloaded['chatId'] as int;
                    
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('active_project_id', pId);
                    
                    String prompt = '';
                    final projectsJson = prefs.getString('projects_list');
                    if (projectsJson != null) {
                      try {
                        final decoded = jsonDecode(projectsJson) as List<dynamic>;
                        final proj = decoded.firstWhere((p) => p['id'] == pId, orElse: () => null);
                        if (proj != null) {
                          prompt = proj['prompt'] ?? '';
                        }
                      } catch (_) {}
                    }
                    await prefs.setString('active_project_prompt', prompt);

                    setState(() {
                      _activeProjectId = pId;
                      _currentChatId = cId;
                    });
                    _loadSettings();
                    _loadChats();
                    _loadChat(cId);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.settings_outlined, color: VegaTheme.accent),
                title: Text('Настройки', style: TextStyle(color: VegaTheme.textPrimary)),
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
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IdeScreen()),
              );
            },
            tooltip: 'Режим IDE',
            icon: const Icon(Icons.code_rounded, color: VegaTheme.accent, size: 26),
          ),
          if (_activeProjectId != 'default')
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('active_project_id', 'default');
                  await prefs.setString('active_project_prompt', '');
                  _startNewChat();
                  setState(() {
                    _activeProjectId = 'default';
                  });
                  _loadChats();
                },
                tooltip: 'Вернуться в обычный чат',
                icon: const Icon(Icons.note_alt_outlined, color: VegaTheme.accent, size: 26),
              ),
            )
          else if (!_showNewChatScreen)
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
                    child: SelectionArea(
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
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 12, top: 4),
                            child: ShimmerThinkingIndicator(fontSize: 14),
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
                            onLongPress: isUser
                                ? () => _showUserMessageMenu(context, msg, i)
                                : null,
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
                                                 selectable: false,
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
                                               Builder(builder: (context) {
                                                 final cmd = _extractCommand(msg['content'] ?? '');
                                                 if (cmd != null) {
                                                   return _buildTerminalCard(i, cmd);
                                                 }
                                                 return const SizedBox.shrink();
                                               }),
                                             ],
                                           ),
                                         ),
                              ],
                            ),
                          ),
                          if (!isUser && msg['content']?.isNotEmpty == true && !(_loading && i == _messages.length - 1))
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
                                ? GestureDetector(
                                    onTap: () => showImageViewer(context, imagePath: att['path'] as String, title: att['name'] as String?),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(File(att['path'] as String), width: 64, height: 64, fit: BoxFit.cover),
                                    ),
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
                          hintText: _isListening ? 'Слушаю...' : 'Сообщение...',
                          hintStyle: TextStyle(color: _isListening ? VegaTheme.accent : VegaTheme.textSecondary),
                          filled: true,
                          fillColor: VegaTheme.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
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
                            final hasContent = _isTyping || _attachedFiles.isNotEmpty;
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
                _copied ? 'Скопировано!' : 'Копировать',
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

class EditMessageDialog extends StatefulWidget {
  final String initialText;
  final List<String> initialFilePaths;
  final List<String> initialFileNames;
  final String initialFilePath;
  final String initialFileName;
  final bool initialIsImage;
  final Future<String> Function(String sourcePath, String fileName) copyFileToAppDir;

  const EditMessageDialog({
    super.key,
    required this.initialText,
    required this.initialFilePaths,
    required this.initialFileNames,
    required this.initialFilePath,
    required this.initialFileName,
    required this.initialIsImage,
    required this.copyFileToAppDir,
  });

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final TextEditingController _textController;
  final List<Map<String, dynamic>> _attachments = [];

  @override
  void initState() {
    super.initState();
    final cleanText = widget.initialText.replaceAll(
      RegExp(r'!\[image\]\(data:[^)]+\)'), 
      ''
    ).trim();
    _textController = TextEditingController(text: cleanText);

    if (widget.initialFilePaths.isNotEmpty) {
      for (int i = 0; i < widget.initialFilePaths.length; i++) {
        final path = widget.initialFilePaths[i];
        final name = widget.initialFileNames.length > i ? widget.initialFileNames[i] : 'file';
        final isImg = path.toLowerCase().endsWith('.png') ||
            path.toLowerCase().endsWith('.jpg') ||
            path.toLowerCase().endsWith('.jpeg') ||
            path.toLowerCase().endsWith('.gif');
        _attachments.add({'path': path, 'name': name, 'isImage': isImg});
      }
    } else if (widget.initialFilePath.isNotEmpty) {
      _attachments.add({
        'path': widget.initialFilePath,
        'name': widget.initialFileName,
        'isImage': widget.initialIsImage,
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
    if (result != null) {
      for (final f in result.files) {
        if (f.path == null) continue;
        final savedPath = await widget.copyFileToAppDir(f.path!, f.name);
        setState(() => _attachments.add({'path': savedPath, 'name': f.name, 'isImage': false}));
      }
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    for (final image in images) {
      final savedPath = await widget.copyFileToAppDir(image.path, image.name);
      setState(() => _attachments.add({'path': savedPath, 'name': image.name, 'isImage': true}));
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VegaTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: VegaTheme.accent),
              title: const Text('Фото'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: VegaTheme.accent),
              title: const Text('Файл'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFiles();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VegaTheme.surface,
      title: const Text('Редактировать сообщение', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              maxLines: 6,
              minLines: 1,
              style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.attach_file, color: VegaTheme.textSecondary),
                  onPressed: _showAttachMenu,
                ),
              ),
            ),
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Вложения:', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              SizedBox(
                height: 70,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  itemBuilder: (ctx, i) {
                    final att = _attachments[i];
                    final isImg = att['isImage'] == true;
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          isImg
                              ? GestureDetector(
                                  onTap: () => showImageViewer(context, imagePath: att['path'] as String, title: att['name'] as String?),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(File(att['path'] as String), width: 60, height: 60, fit: BoxFit.cover),
                                  ),
                                )
                              : Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(color: VegaTheme.card, borderRadius: BorderRadius.circular(8)),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 20),
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Text(
                                          att['name'] as String,
                                          style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 8),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          Positioned(
                            top: -4,
                            right: -4,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _attachments.removeAt(i);
                                });
                              },
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                padding: const EdgeInsets.all(3),
                                child: const Icon(Icons.close, color: Colors.white, size: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            final newText = _textController.text.trim();
            Navigator.pop(context, {
              'text': newText,
              'attachments': _attachments,
            });
          },
          child: const Text('Отправить', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
