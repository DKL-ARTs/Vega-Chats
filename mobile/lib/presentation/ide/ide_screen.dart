import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // Required for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markdown/markdown.dart' as md;
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
import 'package:url_launcher/url_launcher.dart';
import 'editor_screen.dart';
import 'phone_file_browser.dart';
import '../terminal/terminal_screen.dart';
import '../agent/agent_screen.dart';

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
  String _fileSearchQuery = '';
  final Map<String, String> _originalFileContents = {};

  // === GIT STATE ===
  String _activeDrawerTab = 'files'; // 'files' | 'phone' | 'git' | 'search'
  List<Map<String, dynamic>> _gitFiles = [];
  bool _gitLoading = false;
  bool _gitIsRepo = true;
  final _gitMsgCtrl = TextEditingController();
  bool _gitPushing = false;
  List<String> _gitBranches = [];
  String _gitCurrentBranch = 'main';

  // === SEARCH STATE ===
  final _searchCtrl = TextEditingController();
  bool _searchLoading = false;
  List<Map<String, dynamic>> _searchResults = [];
  String _searchError = '';
  String _lastSearchQuery = '';

  // === AI DEV CHAT STATE ===
  int? _ideChatId;
  List<Map<String, dynamic>> _chatMessages = [];
  List<Map<String, dynamic>> _ideChats = [];
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
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
  String _preListeningText = '';
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
    final workspaceRoot = prefs.getString('workspace_root') ?? '/root/workspace';
    setState(() {
      _client.baseUrl = baseUrl;
      _client.apiKey = apiKey;
      _currentPath = workspaceRoot;
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
    _searchController.dispose();
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

  String _formatDictation(String input) {
    var formatted = input;
    final replacements = {
      ' запятая': ',',
      'запятая': ',',
      ' точка': '.',
      'точка': '.',
      ' знак вопроса': '?',
      'знак вопроса': '?',
      ' знак восклицания': '!',
      'знак восклицания': '!',
      ' двоеточие': ':',
      'двоеточие': ':',
      ' новая строка': '\n',
      'новая строка': '\n',
      ' абзац': '\n',
      'абзац': '\n',
    };
    
    replacements.forEach((key, val) {
      formatted = formatted.replaceAll(key, val);
      formatted = formatted.replaceAll(key[0].toUpperCase() + key.substring(1), val);
    });
    return formatted;
  }

  void _startListening() async {
    if (!_speechEnabled) {
      await _initSpeech();
    }
    if (_speechEnabled) {
      _preListeningText = _chatInputCtrl.text;
      setState(() => _isListening = true);
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _lastWords = _formatDictation(result.recognizedWords);
            if (_lastWords.isNotEmpty) {
              _chatInputCtrl.text = _preListeningText + 
                  (_preListeningText.isEmpty ? "" : (_preListeningText.endsWith('\n') ? "" : " ")) + 
                  _lastWords;
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

  Future<void> _loadGitStatus() async {
    setState(() {
      _gitLoading = true;
    });
    try {
      final res = await _client.gitStatus(cwd: _currentPath);
      if (res['ok'] == true) {
        setState(() {
          _gitFiles = List<Map<String, dynamic>>.from(res['files'] ?? []);
          _gitIsRepo = true;
        });
        
        // Load branches in the background
        final branchRes = await _client.gitBranches(cwd: _currentPath);
        if (branchRes['ok'] == true && mounted) {
          setState(() {
            _gitBranches = List<String>.from(branchRes['branches'] ?? []);
            _gitCurrentBranch = branchRes['current'] ?? 'main';
          });
        }
      } else {
        setState(() {
          _gitIsRepo = false;
          _gitFiles = [];
        });
      }
    } catch (_) {
      setState(() {
        _gitIsRepo = false;
        _gitFiles = [];
      });
    } finally {
      setState(() {
        _gitLoading = false;
      });
    }
  }

  Future<void> _initializeGitRepo() async {
    setState(() => _gitLoading = true);
    try {
      final res = await _client.gitInit(_currentPath);
      if (res['ok'] == true) {
        _loadGitStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка Git Init: ${res['error']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка Git Init: $e')),
      );
    } finally {
      setState(() => _gitLoading = false);
    }
  }

  Future<void> _commitAndPushGit() async {
    final msg = _gitMsgCtrl.text.trim();
    if (msg.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Введите сообщение коммита'), backgroundColor: Colors.orangeAccent),
       );
       return;
    }
    setState(() => _gitPushing = true);
    try {
      final res = await _client.gitCommitPush(msg, cwd: _currentPath);
      if (res['ok'] == true) {
        _gitMsgCtrl.clear();
        _loadGitStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Успешно отправлено на GitHub!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка отправки: ${res['error']}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _gitPushing = false);
      }
    }
  }

  Future<void> _gitPull() async {
    setState(() => _gitLoading = true);
    try {
      final res = await _client.gitPull(cwd: _currentPath);
      if (res['ok'] == true) {
        _loadGitStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Успешно стянуто (Pull) с GitHub!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка Pull: ${res['error']}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка Pull: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _gitLoading = false);
    }
  }

  Future<void> _toggleStageUnstage(Map<String, dynamic> file) async {
    final status = file['status'] ?? '';
    final path = file['path'] ?? '';
    // A staged status starts with A, M, D and does NOT have a space at the start
    final isStaged = status.isNotEmpty && !status.startsWith(' ') && !status.startsWith('?');
    
    setState(() => _gitLoading = true);
    try {
      final res = isStaged 
          ? await _client.gitUnstage(path, cwd: _currentPath)
          : await _client.gitStage(path, cwd: _currentPath);
      if (res['ok'] == true) {
        _loadGitStatus();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка изменения индекса: ${res['error']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      setState(() => _gitLoading = false);
    }
  }

  Future<void> _showGitFileDiff(String path) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        backgroundColor: VegaTheme.surface,
        content: Row(
          children: [
            CircularProgressIndicator(color: VegaTheme.accent),
            SizedBox(width: 16),
            Text('Загрузка diff...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final res = await _client.gitDiff(filePath: path, cwd: _currentPath);
      if (mounted) Navigator.pop(context); // Close loading dialog

      if (res['ok'] == true) {
        final diffText = res['diff'] as String? ?? '';
        final diffLines = diffText.split('\n');

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: VegaTheme.surface,
              title: Text('Diff: $path', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: diffText.trim().isEmpty
                    ? const Center(child: Text('Нет изменений во встроенном diff (возможно, файл бинарный или пустой)', style: TextStyle(color: Colors.white54, fontSize: 12)))
                    : Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ListView.builder(
                          itemCount: diffLines.length,
                          itemBuilder: (context, idx) {
                            final line = diffLines[idx];
                            Color color = Colors.white70;
                            if (line.startsWith('+')) {
                              color = Colors.greenAccent;
                            } else if (line.startsWith('-')) {
                              color = Colors.redAccent;
                            } else if (line.startsWith('@@')) {
                              color = Colors.cyanAccent;
                            }
                            return Text(
                              line,
                              style: TextStyle(
                                color: color,
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                height: 1.3,
                              ),
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Закрыть', style: TextStyle(color: VegaTheme.accent)),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка загрузки diff: ${res['error']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _showBranchSelector() async {
    final branchNameCtrl = TextEditingController();
    final newBranchCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: VegaTheme.surface,
          title: const Text('Управление ветками Git', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Текущая ветка:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text(
                  _gitCurrentBranch,
                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text('Переключиться на ветку:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                _gitBranches.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Загрузка веток...', style: TextStyle(color: Colors.white30, fontSize: 12)),
                      )
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _gitBranches.length,
                          itemBuilder: (ctx, i) {
                            final b = _gitBranches[i];
                            final isCurrent = b == _gitCurrentBranch;
                            return ListTile(
                              dense: true,
                              title: Text(
                                b,
                                style: TextStyle(
                                  color: isCurrent ? Colors.blueAccent : Colors.white70,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              trailing: isCurrent ? const Icon(Icons.check, color: Colors.blueAccent, size: 16) : null,
                              onTap: isCurrent
                                  ? null
                                  : () async {
                                      Navigator.pop(ctx);
                                      setState(() => _gitLoading = true);
                                      try {
                                        final checkoutRes = await _client.gitCheckout(b, cwd: _currentPath);
                                        if (checkoutRes['ok'] == true) {
                                          _loadGitStatus();
                                        } else {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Ошибка переключения: ${checkoutRes['error']}')),
                                            );
                                          }
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Ошибка: $e')),
                                          );
                                        }
                                      } finally {
                                        setState(() => _gitLoading = false);
                                      }
                                    },
                            );
                          },
                        ),
                      ),
                const SizedBox(height: 16),
                const Text('Создать новую ветку:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newBranchCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Имя ветки...',
                          hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: () async {
                        final newBranch = newBranchCtrl.text.trim();
                        if (newBranch.isNotEmpty) {
                          Navigator.pop(ctx);
                          setState(() => _gitLoading = true);
                          try {
                            final checkoutRes = await _client.gitCheckout(newBranch, create: true, cwd: _currentPath);
                            if (checkoutRes['ok'] == true) {
                              _loadGitStatus();
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка создания ветки: ${checkoutRes['error']}')),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Ошибка: $e')),
                              );
                            }
                          } finally {
                            setState(() => _gitLoading = false);
                          }
                        }
                      },
                      child: const Text('Создать', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
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
      _handleEditorResult(result);
    }
  }

  Future<void> _triggerAiAction(String actionType, String filePath, String fileName) async {
    setState(() {
      _chatLoading = true;
    });
    try {
      final res = await _client.readFile(filePath);
      final content = res['content'] ?? '';
      
      String prompt = '';
      if (actionType == 'explain') {
        prompt = 'Объясни, как работает этот код в файле $fileName:\n\n```\n$content\n```';
      } else if (actionType == 'tests') {
        prompt = 'Напиши модульные тесты для кода в файле $fileName:\n\n```\n$content\n```';
      } else if (actionType == 'refactor') {
        prompt = 'Сделай рефакторинг и оптимизацию кода в файле $fileName для улучшения читаемости и производительности:\n\n```\n$content\n```';
      } else if (actionType == 'bugs') {
        prompt = 'Проведи статический анализ и найди потенциальные баги или уязвимости в коде файла $fileName:\n\n```\n$content\n```';
      }

      if (prompt.isNotEmpty) {
        _chatInputCtrl.text = prompt;
        await _sendChatMessage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при выполнении действия: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _chatLoading = false;
        });
      }
    }
  }

  void _handleEditorResult(dynamic result) {
    if (result is Map<String, dynamic> && result.containsKey('action')) {
      final action = result['action'];
      final path = result['path'];
      final name = result['name'];
      _triggerAiAction(action, path, name);
    } else if (result == true) {
      _loadFiles();
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
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditorScreen(filePath: fullPath, fileName: name),
                      ),
                    );
                    _handleEditorResult(result);
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

  void _createNewFolder() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: const Text(
          'Новая папка',
          style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Имя папки',
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
                final folderPath = '$_currentPath/$name';
                try {
                  // Create placeholder .keep file to force creation of folder via API
                  await _client.writeFile('$folderPath/.keep', '');
                  _loadFiles();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка создания папки: $e'), backgroundColor: Colors.redAccent),
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

  Future<void> _setAsWorkspaceRoot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workspace_root', _currentPath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('Папка "$_currentPath" установлена как рабочая!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteFileOrDir(Map<String, dynamic> item) async {
    final fullPath = '$_currentPath/${item['name']}';
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: const Text('Удаление', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Вы уверены, что хотите удалить ${item['is_dir'] == true ? 'папку' : 'файл'} "${item['name']}"?',
          style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _client.deleteFile(fullPath);
        _loadFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Успешно удалено'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка удаления: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _renameFileOrDir(Map<String, dynamic> item) async {
    final oldPath = '$_currentPath/${item['name']}';
    final controller = TextEditingController(text: item['name']);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: const Text('Переименование', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Новое имя',
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
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != item['name']) {
                Navigator.pop(ctx);
                final newPath = '$_currentPath/$newName';
                try {
                  await _client.renameFile(oldPath, newPath);
                  _loadFiles();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка переименования: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
              }
            },
            child: const Text('Сохранить', style: TextStyle(color: VegaTheme.accent)),
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
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.70,
            child: TerminalScreen(
              embedMode: true,
              onClose: () => Navigator.pop(ctx),
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
    await prefs.remove('ide_chat_id'); // Ensure it is cleared

    // Every time we enter the IDE, start in a completely new, empty chat session
    _ideChatId = null;
    _chatMessages = [];
    await _loadIdeChats(); // Load existing chats for the drawer list
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
    allChats.sort((a, b) {
      final aPinned = a['pinned'] == true;
      final bPinned = b['pinned'] == true;
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      return (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? '');
    });
    setState(() {
      _ideChats = allChats.where((c) => c['projectId'] == 'ide').toList();
    });
  }

  Future<void> _togglePinChat(int chatId) async {
    await ChatHistory.togglePinChat(chatId);
    await _loadIdeChats();
  }

  Future<void> _deleteChat(int chatId) async {
    await ChatHistory.deleteChat(chatId);
    if (_ideChatId == chatId) {
      // Don't auto-create: just clear the active chat
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ide_chat_id');
      setState(() {
        _ideChatId = null;
        _chatMessages.clear();
      });
    }
    await _loadIdeChats();
  }

  void _renameChat(int chatId, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: const Text(
          'Переименовать чат',
          style: TextStyle(color: VegaTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
          decoration: const InputDecoration(
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
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                Navigator.pop(ctx);
                await ChatHistory.updateChatTitle(chatId, newTitle);
                await _loadIdeChats();
              }
            },
            child: const Text('Сохранить', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _createNewIdeChat() {
    // Just clear the state — chat will be created in DB on first message send
    setState(() {
      _ideChatId = null;
      _chatMessages.clear();
    });
    if (mounted) Navigator.pop(context); // Close drawer
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
    if (_chatLoading) return;

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

    // Lazy chat creation: create on first message if no chat exists yet
    if (_ideChatId == null) {
      final displayText = text.isNotEmpty ? text : msgContent;
      final title = displayText.length > 30 ? '${displayText.substring(0, 30)}...' : displayText;
      final chatId = await ChatHistory.createChat(title, projectId: 'ide');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ide_chat_id', chatId);
      setState(() => _ideChatId = chatId);
      await _loadIdeChats();
    }

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
        // Auto-save any [WRITE_FILE:...] blocks to workspace
        await _processWriteFiles(finalResponse);
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

  List<Map<String, String>> _extractAllGeneratedFiles(String content) {
    final List<Map<String, String>> list = [];
    final Set<String> seenPaths = {};

    // Pattern A: [WRITE_FILE:path]content[/WRITE_FILE]
    final patternA = RegExp(r'\[WRITE_FILE:([^\]]+)\]([\s\S]*?)\[/WRITE_FILE\]');
    for (final match in patternA.allMatches(content)) {
      final path = match.group(1)?.trim() ?? '';
      final fileContent = match.group(2) ?? '';
      if (path.isNotEmpty && !seenPaths.contains(path)) {
        seenPaths.add(path);
        final name = path.split('/').last;
        list.add({'name': name, 'path': path, 'content': fileContent});
      }
    }

    // Pattern B: [Скачать file](downloadLink)
    final patternB = RegExp(r'\[([^\]]*?)\]\(/api/files/download\?path=([^)]+)\)');
    for (final match in patternB.allMatches(content)) {
      final name = match.group(1) ?? 'file';
      final path = match.group(2) ?? '';
      if (path.isNotEmpty && !seenPaths.contains(path)) {
        seenPaths.add(path);
        String cleanName = name.replaceAll('Скачать ', '').replaceAll('файл ', '').replaceAll('`', '').trim();
        list.add({'name': cleanName, 'path': path, 'content': ''});
      }
    }

    return list;
  }

  /// Renders animated file cards for each generated/downloadable file block
  Widget _buildWrittenFileCards(String content) {
    final files = _extractAllGeneratedFiles(content);
    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: files.map((file) {
        final filePath = file['path'] ?? '';
        final fileName = file['name'] ?? 'file';
        final fileContent = file['content'] ?? '';
        final originalContent = _originalFileContents[filePath];
        return _FileCard(
          filePath: filePath,
          fileName: fileName,
          fileContent: fileContent,
          originalContent: originalContent,
          client: _client,
          onSaved: _loadFiles,
        );
      }).toList(),
    );
  }

  /// Parses [WRITE_FILE:path]content[/WRITE_FILE] blocks from AI response
  /// and saves each file to the workspace via the backend Files API.
  Future<void> _processWriteFiles(String response) async {
    final pattern = RegExp(r'\[WRITE_FILE:([^\]]+)\]([\s\S]*?)\[/WRITE_FILE\]');
    final matches = pattern.allMatches(response);
    if (matches.isEmpty) return;

    bool anyWritten = false;
    for (final match in matches) {
      final filePath = match.group(1)?.trim() ?? '';
      final fileContent = match.group(2) ?? '';
      if (filePath.isEmpty) continue;
      try {
        // Read original file content first (if it exists)
        try {
          final res = await _client.readFile(filePath);
          if (res.containsKey('content') && res['content'] != null) {
            _originalFileContents[filePath] = res['content'] as String;
          }
        } catch (_) {
          // File does not exist yet (new file)
        }

        await _client.writeFile(filePath, fileContent);
        anyWritten = true;
      } catch (e) {
        debugPrint('WRITE_FILE error: $e');
      }
    }
    // Refresh the file explorer after writing
    if (anyWritten) await _loadFiles();
  }

  String _cleanMessageContent(String content) {
    String cleaned = content;
    cleaned = cleaned.replaceAll(RegExp(r'\[WRITE_FILE:.*?\][\s\S]*?\[/WRITE_FILE\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[WRITE_FILE:.*?\]'), '');
    cleaned = cleaned.replaceAll('[/WRITE_FILE]', '');
    cleaned = cleaned.replaceAll(RegExp(r'WRITE_FILE:.*?\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'<execute_command>[\s\S]*?</execute_command>'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*?\]\(/api/files/download\?path=[^)]+\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'Вы можете\s*$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'Вы можете\s*\n'), '');
    cleaned = cleaned.replaceAll(RegExp(r'### 💾 Создан файл.*?\n'), '');
    cleaned = cleaned.replaceAll(RegExp(r'### 💾 Создан файл.*?$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'💾 Создан файл.*?\n'), '');
    cleaned = cleaned.replaceAll(RegExp(r'💾 Создан файл.*?$'), '');
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
        await _processWriteFiles(finalResponse);
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
                if (!_chatHasText) ...[
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
            // Tab Selector
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeDrawerTab = 'files';
                        });
                        _loadFiles();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeDrawerTab == 'files' ? VegaTheme.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _activeDrawerTab == 'files' ? VegaTheme.accent : Colors.white10,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Проводник',
                          style: TextStyle(
                            color: _activeDrawerTab == 'files' ? Colors.white : VegaTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeDrawerTab = 'phone'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeDrawerTab == 'phone' ? const Color(0xFF22C55E) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _activeDrawerTab == 'phone' ? const Color(0xFF22C55E) : Colors.white10,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_android_rounded, size: 12,
                              color: _activeDrawerTab == 'phone' ? Colors.white : VegaTheme.textSecondary),
                            const SizedBox(width: 3),
                            Text(
                              'Телефон',
                              style: TextStyle(
                                color: _activeDrawerTab == 'phone' ? Colors.white : VegaTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _activeDrawerTab = 'git';
                        });
                        _loadGitStatus();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeDrawerTab == 'git' ? VegaTheme.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _activeDrawerTab == 'git' ? VegaTheme.accent : Colors.white10,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Git',
                          style: TextStyle(
                            color: _activeDrawerTab == 'git' ? Colors.white : VegaTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeDrawerTab = 'search'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeDrawerTab == 'search' ? const Color(0xFFF59E0B) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _activeDrawerTab == 'search' ? const Color(0xFFF59E0B) : Colors.white10,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_rounded, size: 12,
                              color: _activeDrawerTab == 'search' ? Colors.white : VegaTheme.textSecondary),
                            const SizedBox(width: 3),
                            Text(
                              'Поиск',
                              style: TextStyle(
                                color: _activeDrawerTab == 'search' ? Colors.white : VegaTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 12),
            
            // Conditional tab content
            Expanded(
              child: _activeDrawerTab == 'files'
                  ? Column(
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Проводник файлов',
                                style: TextStyle(color: VegaTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: _setAsWorkspaceRoot,
                                    icon: const Icon(Icons.home_work_rounded, color: Colors.greenAccent, size: 20),
                                    tooltip: 'Установить как рабочую папку',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                  ),
                                  IconButton(
                                    onPressed: _createNewFolder,
                                    icon: const Icon(Icons.create_new_folder_rounded, color: VegaTheme.accent, size: 20),
                                    tooltip: 'Создать папку',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                  ),
                                  IconButton(
                                    onPressed: _createNewFile,
                                    icon: const Icon(Icons.note_add_rounded, color: VegaTheme.accent, size: 20),
                                    tooltip: 'Создать файл',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                  ),
                                ],
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
                              if (_currentPath != '/' && _currentPath.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    final parts = _currentPath.split('/');
                                    if (parts.isNotEmpty) {
                                      parts.removeLast();
                                      final newPath = parts.join('/');
                                      setState(() => _currentPath = newPath.isEmpty ? '/' : newPath);
                                      _loadFiles();
                                    }
                                  },
                                  child: const Text('Назад', style: TextStyle(color: VegaTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                                )
                            ],
                          ),
                        ),
                        // Search bar
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
                        // Files List
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
                                              leading: Icon(
                                                isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                                                color: isDir ? VegaTheme.accent : VegaTheme.textSecondary,
                                                size: 20,
                                              ),
                                              title: Text(
                                                item['name'],
                                                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13),
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (!isDir)
                                                    Text(
                                                      '${item['size']} B',
                                                      style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 10),
                                                    ),
                                                  PopupMenuButton<String>(
                                                    icon: const Icon(Icons.more_vert_rounded, color: VegaTheme.textSecondary, size: 18),
                                                    color: VegaTheme.surface,
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onSelected: (value) {
                                                      if (value == 'rename') {
                                                        _renameFileOrDir(item);
                                                      } else if (value == 'delete') {
                                                        _deleteFileOrDir(item);
                                                      } else if (value.startsWith('ai_')) {
                                                        final actionType = value.substring(3);
                                                        final fullPath = '$_currentPath/${item['name']}';
                                                        Navigator.pop(context); // Close endDrawer explorer
                                                        _triggerAiAction(actionType, fullPath, item['name']);
                                                      }
                                                    },
                                                    itemBuilder: (context) => [
                                                      const PopupMenuItem(
                                                        value: 'rename',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.edit_rounded, color: VegaTheme.textPrimary, size: 16),
                                                            SizedBox(width: 8),
                                                            Text('Переименовать', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                                          ],
                                                        ),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'delete',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.delete_rounded, color: Colors.redAccent, size: 16),
                                                            SizedBox(width: 8),
                                                            Text('Удалить', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                                          ],
                                                        ),
                                                      ),
                                                      if (!isDir) ...[
                                                        const PopupMenuDivider(),
                                                        const PopupMenuItem(
                                                          value: 'ai_explain',
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.psychology_rounded, color: Colors.amberAccent, size: 16),
                                                              SizedBox(width: 8),
                                                              Text('Объяснить код', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'ai_tests',
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.science_rounded, color: Colors.amberAccent, size: 16),
                                                              SizedBox(width: 8),
                                                              Text('Написать тесты', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'ai_refactor',
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.build_circle_rounded, color: Colors.amberAccent, size: 16),
                                                              SizedBox(width: 8),
                                                              Text('Рефакторинг', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'ai_bugs',
                                                          child: Row(
                                                            children: [
                                                              Icon(Icons.bug_report_rounded, color: Colors.amberAccent, size: 16),
                                                              SizedBox(width: 8),
                                                              Text('Найти баги', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              onTap: () => _openFileItem(item),
                                            );
                                          },
                                        );
                                }(),
                        ),
                      ],
                    )
                  : _activeDrawerTab == 'phone'
                      ? PhoneFileBrowser(
                          client: _client,
                          onOpenInEditor: (filePath, fileName, content) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditorScreen(
                                  fileName: fileName,
                                  initialContent: content,
                                  filePath: filePath,
                                  isPhoneFile: true,
                                ),
                              ),
                            );
                          },
                          onAiAction: (actionType, filePath, fileName) async {
                            try {
                              final content = await File(filePath).readAsString();
                              final prompts = {
                                'explain': 'Объясни этот код из файла $fileName:\n\n```\n$content\n```',
                                'tests': 'Напиши юнит-тесты для кода из файла $fileName:\n\n```\n$content\n```',
                                'refactor': 'Отрефактори этот код из файла $fileName и объясни изменения:\n\n```\n$content\n```',
                                'bugs': 'Найди баги и проблемы в коде из файла $fileName:\n\n```\n$content\n```',
                              };
                              final prompt = prompts[actionType] ?? 'Проанализируй файл $fileName';
                              setState(() {
                                _chatInputCtrl.text = prompt;
                              });
                              Navigator.pop(context); // Close drawer
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          },
                        )
                      : _activeDrawerTab == 'git'
                          ? _buildGitTab()
                          : _buildSearchTab(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searchLoading = true;
      _searchError = '';
      _searchResults = [];
      _lastSearchQuery = query;
    });
    try {
      final res = await _client.searchInFiles(query, cwd: _currentPath);
      if (res['ok'] == true) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(res['results'] ?? []);
        });
      } else {
        setState(() => _searchError = res['error'] ?? 'Ошибка поиска');
      }
    } catch (e) {
      setState(() => _searchError = e.toString());
    } finally {
      setState(() => _searchLoading = false);
    }
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        // Search input
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Поиск по проекту...',
                      hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      prefixIcon: Icon(Icons.search_rounded, size: 16, color: VegaTheme.textSecondary),
                    ),
                    onSubmitted: (_) => _runSearch(),
                    textInputAction: TextInputAction.search,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _runSearch,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _searchLoading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.search_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
        // Error
        if (_searchError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(_searchError,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        // Stats
        if (_searchResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 12, color: VegaTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${_searchResults.length} файл(ов) для "$_lastSearchQuery"',
                  style: TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        // Empty state
        if (_searchResults.isEmpty && !_searchLoading && _lastSearchQuery.isNotEmpty && _searchError.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, size: 40, color: VegaTheme.textSecondary.withOpacity(0.4)),
                const SizedBox(height: 8),
                Text('Ничего не найдено', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        if (_searchResults.isEmpty && !_searchLoading && _lastSearchQuery.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.manage_search_rounded, size: 40, color: VegaTheme.textSecondary.withOpacity(0.3)),
                const SizedBox(height: 8),
                Text('Введите запрос для поиска\nпо всем файлам проекта',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        // Results list
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (context, i) {
              final fileResult = _searchResults[i];
              final fileName = fileResult['file'] as String? ?? '';
              final fullPath = fileResult['full_path'] as String? ?? '';
              final matches = List<Map<String, dynamic>>.from(fileResult['matches'] ?? []);
              return Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  childrenPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.insert_drive_file_rounded,
                        size: 12, color: Color(0xFFF59E0B)),
                  ),
                  title: Text(
                    fileName,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${matches.length}',
                        style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  ),
                  initiallyExpanded: _searchResults.length <= 3,
                  children: matches.map((match) {
                    final lineNum = match['line'] as int? ?? 0;
                    final content = match['content'] as String? ?? '';
                    // Highlight the query
                    final query = _lastSearchQuery;
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context); // close drawer
                        final fileContent = await _client.readFile(fullPath);
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditorScreen(
                              fileName: fileName.split('/').last,
                              initialContent: fileContent['content'] as String? ?? '',
                              filePath: fullPath,
                              client: _client,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$lineNum',
                              style: TextStyle(
                                color: const Color(0xFFF59E0B).withOpacity(0.7),
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildHighlightedLine(content, query),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightedLine(String text, String query) {
    if (query.isEmpty) {
      return Text(text,
          style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);
    if (idx == -1) {
      return Text(text,
          style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis);
    }
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        children: [
          TextSpan(text: text.substring(0, idx),
              style: const TextStyle(color: Colors.white60)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: const TextStyle(
              color: Color(0xFFF59E0B),
              backgroundColor: Color(0x33F59E0B),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(idx + query.length),
              style: const TextStyle(color: Colors.white60)),
        ],
      ),
    );
  }

  Widget _buildGitTab() {
    if (_gitLoading) {
      return const Center(child: CircularProgressIndicator(color: VegaTheme.accent));
    }

    if (!_gitIsRepo) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Не является Git репозиторием',
              textAlign: TextAlign.center,
              style: TextStyle(color: VegaTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Инициализируйте репозиторий, чтобы управлять изменениями.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _initializeGitRepo,
              icon: const Icon(Icons.merge_type_rounded, size: 16, color: Colors.white),
              label: const Text('Инициализировать Git', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: VegaTheme.accent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Changed files list header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Изменения (${_gitFiles.length})',
                    style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showBranchSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fork_right_rounded, color: Colors.blueAccent, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            _gitCurrentBranch,
                            style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _gitPull,
                    icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                    tooltip: 'Pull с GitHub',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  IconButton(
                    onPressed: _loadGitStatus,
                    icon: const Icon(Icons.refresh_rounded, color: VegaTheme.textSecondary, size: 18),
                    tooltip: 'Обновить статус',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Changed files list
        Expanded(
          child: _gitFiles.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 36),
                      SizedBox(height: 8),
                      Text('Нет изменений для фиксации', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _gitFiles.length,
                  itemBuilder: (ctx, i) {
                    final file = _gitFiles[i];
                    final status = file['status'] ?? '';
                    final path = file['path'] ?? '';
                    
                    Color statusColor;
                    String statusLetter;
                    if (status.contains('M') || status.contains('AM')) {
                      statusColor = Colors.amberAccent;
                      statusLetter = 'M';
                    } else if (status.contains('A') || status.contains('?')) {
                      statusColor = Colors.greenAccent;
                      statusLetter = status.contains('?') ? 'U' : 'A';
                    } else if (status.contains('D')) {
                      statusColor = Colors.redAccent;
                      statusLetter = 'D';
                    } else {
                      statusColor = VegaTheme.textSecondary;
                      statusLetter = status;
                    }

                    final isStaged = status.isNotEmpty && !status.startsWith(' ') && !status.startsWith('?');
                    return ListTile(
                      onTap: () => _showGitFileDiff(path),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: Icon(Icons.insert_drive_file_rounded, color: statusColor, size: 18),
                      title: Text(
                        path,
                        style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 12, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: statusColor.withOpacity(0.3), width: 0.5),
                            ),
                            child: Text(
                              statusLetter,
                              style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => _toggleStageUnstage(file),
                            icon: Icon(
                              isStaged ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                              color: isStaged ? Colors.redAccent : Colors.greenAccent,
                              size: 16,
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            tooltip: isStaged ? 'Убрать из индекса' : 'Добавить в индекс',
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        // Commit & Push input area
        if (_gitFiles.isNotEmpty)
          Container(
            color: VegaTheme.surface,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _gitMsgCtrl,
                  style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 12.5),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Сообщение коммита...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12.5),
                    fillColor: VegaTheme.dark,
                    filled: true,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: VegaTheme.border, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: VegaTheme.accent, width: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _gitPushing ? null : _commitAndPushGit,
                  icon: _gitPushing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 16, color: Colors.white),
                  label: Text(
                    _gitPushing ? 'Отправка...' : 'Зафиксировать и Пуш',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VegaTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildChatsDrawer() {
    return Drawer(
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
                  const Text(
                    'Чаты IDE',
                    style: TextStyle(color: VegaTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
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
                        icon: const Icon(Icons.add, color: VegaTheme.accent),
                        onPressed: _createNewIdeChat,
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
                  style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск чатов...',
                    hintStyle: const TextStyle(color: VegaTheme.textSecondary),
                    filled: true,
                    fillColor: VegaTheme.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    prefixIcon: const Icon(Icons.search, color: VegaTheme.textSecondary, size: 20),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                ),
              ),
            Expanded(
              child: Builder(builder: (ctx) {
                if (_ideChats.isEmpty) {
                  return const Center(child: Text('Нет активных сессий', style: TextStyle(color: VegaTheme.textSecondary)));
                }

                final filtered = _searchQuery.isEmpty
                    ? _ideChats
                    : _ideChats.where((c) => (c['title'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('Ничего не найдено', style: TextStyle(color: VegaTheme.textSecondary)));
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final chat = filtered[i];
                    final isActive = chat['id'] == _ideChatId;
                    return ListTile(
                      selected: isActive,
                      selectedTileColor: VegaTheme.card,
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      contentPadding: const EdgeInsets.only(left: 16, right: 4),
                      title: Row(
                        children: [
                          if (chat['pinned'] == true) ...[
                            const Icon(Icons.push_pin, color: VegaTheme.accent, size: 12),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              chat['title'] ?? 'Без названия',
                              style: TextStyle(
                                color: isActive ? VegaTheme.accent : VegaTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: VegaTheme.textSecondary, size: 18),
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
                                  Text(isPinned ? 'Открепить' : 'Закрепить', style: const TextStyle(color: VegaTheme.textPrimary)),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'rename',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_outlined, color: VegaTheme.textSecondary, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('Переименовать', style: TextStyle(color: VegaTheme.textPrimary)),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('Удалить', style: TextStyle(color: VegaTheme.textPrimary)),
                                ],
                              ),
                            ),
                          ];
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
                );
              }),
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
      drawer: _buildChatsDrawer(),
      endDrawer: _buildFilesDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.forum_outlined, color: VegaTheme.accent, size: 24),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: 'Чаты IDE',
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            // Files drawer open button (opens right endDrawer)
            IconButton(
              icon: const Icon(Icons.folder_open_rounded, color: VegaTheme.accent, size: 24),
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
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
          // Agent mode button
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AgentScreen(
                    client: _client,
                    initialCwd: _currentPath,
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Агент',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, color: VegaTheme.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Выйти из IDE',
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
              child: _chatMessages.isEmpty
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
                                  builders: {
                                    'pre': CodeBlockBuilder(),
                                  },
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
                            
                            // File cards for WRITE_FILE blocks
                            if (!isUser)
                              _buildWrittenFileCards(content),
                            
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

  TextSpan _parseAnsiText(String line, TextStyle baseStyle) {
    if (!line.contains('\u001b') && !line.contains('\x1B')) {
      Color textColor = baseStyle.color ?? const Color(0xFFE2E8F0);
      FontWeight fontWeight = baseStyle.fontWeight ?? FontWeight.normal;
      
      final lower = line.toLowerCase();
      if (lower.contains('error') || lower.contains('failed') || lower.contains('exception') || lower.contains('ошибка')) {
        textColor = Colors.redAccent;
      } else if (lower.contains('warning') || lower.contains('предупреждение')) {
        textColor = Colors.amber;
      } else if (lower.contains('success') || lower.contains('успешно') || lower.contains('successfully')) {
        textColor = Colors.greenAccent;
      }

      return TextSpan(text: line, style: baseStyle.copyWith(color: textColor, fontWeight: fontWeight));
    }

    final children = <TextSpan>[];
    final pattern = RegExp(r'(?:\x1B|\\u001b)\[([0-9;]*)m');
    final matches = pattern.allMatches(line).toList();
    if (matches.isEmpty) {
      return TextSpan(text: line, style: baseStyle);
    }

    int lastIndex = 0;
    TextStyle currentStyle = baseStyle;

    for (final match in matches) {
      if (match.start > lastIndex) {
        children.add(TextSpan(
          text: line.substring(lastIndex, match.start),
          style: currentStyle,
        ));
      }

      final codeString = match.group(1) ?? '';
      final codes = codeString.split(';');

      Color? foreColor = currentStyle.color;
      FontWeight? fontWeight = currentStyle.fontWeight;

      for (final code in codes) {
        if (code == '0' || code.isEmpty) {
          foreColor = baseStyle.color;
          fontWeight = baseStyle.fontWeight;
        } else if (code == '1') {
          fontWeight = FontWeight.bold;
        } else if (code == '30') {
          foreColor = Colors.black;
        } else if (code == '31') {
          foreColor = Colors.redAccent;
        } else if (code == '32') {
          foreColor = Colors.greenAccent;
        } else if (code == '33') {
          foreColor = Colors.amber;
        } else if (code == '34') {
          foreColor = const Color(0xFF7AA2F7);
        } else if (code == '35') {
          foreColor = Colors.purpleAccent;
        } else if (code == '36') {
          foreColor = Colors.cyanAccent;
        } else if (code == '37') {
          foreColor = Colors.white;
        }
      }

      currentStyle = currentStyle.copyWith(color: foreColor, fontWeight: fontWeight);
      lastIndex = match.end;
    }

    if (lastIndex < line.length) {
      children.add(TextSpan(
        text: line.substring(lastIndex),
        style: currentStyle,
      ));
    }

    return TextSpan(children: children);
  }
}

// ─── Animated file card shown in IDE chat for each WRITE_FILE block ───────────
class _FileCard extends StatefulWidget {
  final String filePath;
  final String fileName;
  final String fileContent;
  final String? originalContent;
  final ApiClient client;
  final VoidCallback? onSaved;

  const _FileCard({
    required this.filePath,
    required this.fileName,
    required this.fileContent,
    this.originalContent,
    required this.client,
    this.onSaved,
  });

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> with SingleTickerProviderStateMixin {
  bool _opened = false;
  bool _downloading = false;
  bool _showDiff = false;
  late AnimationController _checkCtrl;
  late Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _checkAnim = CurvedAnimation(parent: _checkCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    super.dispose();
  }

  void _openFile(BuildContext context) {
    setState(() => _opened = true);
    _checkCtrl.forward();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          filePath: widget.filePath,
          fileName: widget.fileName,
        ),
      ),
    );
  }

  Future<void> _downloadFile(BuildContext context) async {
    setState(() => _downloading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      widget.client.baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8765';
      
      String content = widget.fileContent;
      // If content is empty (e.g. from a download link pattern), fetch it from workspace first
      if (content.isEmpty) {
        final result = await widget.client.readFile(widget.filePath);
        content = result['content'] as String? ?? '';
      }
      
      // Save/write the file content into the workspace (application file list)
      await widget.client.writeFile(widget.filePath, content);
      
      // Call parent reload callback to refresh workspace file explorer drawer
      if (widget.onSaved != null) {
        widget.onSaved!();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Файл сохранен в Проводник файлов: ${widget.fileName}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VegaTheme.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File info row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: VegaTheme.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.insert_drive_file_rounded,
                      color: VegaTheme.accent, // VegaTheme.accent is purple
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        style: const TextStyle(
                          color: VegaTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Generated File',
                        style: TextStyle(
                          color: VegaTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Diff View Toggle & Container
          if (widget.originalContent != null && widget.originalContent != widget.fileContent) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: InkWell(
                onTap: () => setState(() => _showDiff = !_showDiff),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showDiff ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: VegaTheme.accent,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showDiff ? 'Скрыть изменения' : 'Показать изменения',
                        style: const TextStyle(color: VegaTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_showDiff)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: VegaTheme.border, width: 0.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildDiffLines(),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
          // Divider
          Divider(height: 1, color: VegaTheme.border.withOpacity(0.5)),
          // Action buttons row
          IntrinsicHeight(
            child: Row(
              children: [
                // Open button
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openFile(context),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _opened
                            ? Colors.green.withOpacity(0.08)
                            : Colors.transparent,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ScaleTransition(
                            scale: Tween<double>(begin: 1.0, end: 1.0).animate(_checkAnim),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _opened
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: Colors.greenAccent, size: 18, key: ValueKey('check'))
                                  : const Icon(Icons.edit_rounded,
                                      color: VegaTheme.accent, size: 18, key: ValueKey('edit')),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style: TextStyle(
                              color: _opened ? Colors.greenAccent : VegaTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            child: Text(_opened ? 'Редактируется' : 'Редактировать'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Vertical divider
                VerticalDivider(
                  width: 1,
                  color: VegaTheme.border.withOpacity(0.5),
                ),
                // Download button
                Expanded(
                  child: GestureDetector(
                    onTap: _downloading ? null : () => _downloadFile(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _downloading
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: VegaTheme.accent,
                                  ),
                                )
                              : const Icon(Icons.download_rounded,
                                  color: VegaTheme.accent, size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            'Скачать',
                            style: TextStyle(
                              color: VegaTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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

  List<Map<String, dynamic>> _computeLineDiff(String original, String modified) {
    final linesA = original.split('\n');
    final linesB = modified.split('\n');

    final m = linesA.length;
    final n = linesB.length;

    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (linesA[i - 1] == linesB[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    final List<Map<String, dynamic>> diff = [];
    int i = m;
    int j = n;

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && linesA[i - 1] == linesB[j - 1]) {
        diff.insert(0, {'type': 'same', 'text': linesA[i - 1]});
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        diff.insert(0, {'type': 'add', 'text': linesB[j - 1]});
        j--;
      } else {
        diff.insert(0, {'type': 'delete', 'text': linesA[i - 1]});
        i--;
      }
    }

    return diff;
  }

  List<Widget> _buildDiffLines() {
    final diff = _computeLineDiff(widget.originalContent ?? '', widget.fileContent);
    return diff.map((line) {
      Color bg;
      Color textCol;
      String prefix;
      if (line['type'] == 'add') {
        bg = Colors.green.withOpacity(0.15);
        textCol = Colors.greenAccent;
        prefix = '+ ';
      } else if (line['type'] == 'delete') {
        bg = Colors.red.withOpacity(0.15);
        textCol = Colors.redAccent;
        prefix = '- ';
      } else {
        bg = Colors.transparent;
        textCol = const Color(0xFFE2E8F0);
        prefix = '  ';
      }

      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          '$prefix${line['text']}',
          style: TextStyle(
            color: textCol,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      );
    }).toList();
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final textContent = element.textContent;
    String language = 'code';
    if (element.children != null && element.children!.isNotEmpty) {
      final child = element.children!.first;
      if (child is md.Element && child.attributes.containsKey('class')) {
        final className = child.attributes['class'] ?? '';
        if (className.startsWith('language-')) {
          language = className.substring(9).toLowerCase();
        }
      }
    }

    return CodeBlockWidget(code: textContent, language: language);
  }
}

class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;

  const CodeBlockWidget({super.key, required this.code, required this.language});

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _running = false;
  String _status = 'idle'; // 'idle' | 'running' | 'success' | 'error'
  final List<String> _output = [];
  WebSocketChannel? _channel;

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _runCode() async {
    setState(() {
      _running = true;
      _status = 'running';
      _output.clear();
      _output.add('Запуск кода (${widget.language})...\n');
    });

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

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _channel!.stream.listen(
        (data) {
          setState(() {
            _output.add(data.toString());
          });
        },
        onError: (e) {
          setState(() {
            _status = 'error';
            _output.add('\nОшибка WebSocket: $e');
          });
        },
        onDone: () {
          final fullOutput = _output.join('');
          final isError = fullOutput.toLowerCase().contains('failed') || 
                          fullOutput.toLowerCase().contains('error') ||
                          fullOutput.toLowerCase().contains('exception');
          setState(() {
            _status = isError ? 'error' : 'success';
          });
        },
      );

      String command = '';
      if (widget.language == 'python' || widget.language == 'py') {
        command = "cat << 'EOF' > /tmp/run.py\n${widget.code}\nEOF\npython3 /tmp/run.py";
      } else if (widget.language == 'javascript' || widget.language == 'js') {
        command = "cat << 'EOF' > /tmp/run.js\n${widget.code}\nEOF\nnode /tmp/run.js";
      } else if (widget.language == 'bash' || widget.language == 'sh' || widget.language == 'shell') {
        command = "cat << 'EOF' > /tmp/run.sh\n${widget.code}\nEOF\nbash /tmp/run.sh";
      } else {
        command = widget.code;
      }

      _channel!.sink.add(command);
    } catch (e) {
      setState(() {
        _status = 'error';
        _output.add('\nОшибка подключения: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final runnable = ['python', 'py', 'javascript', 'js', 'bash', 'sh', 'shell'].contains(widget.language);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VegaTheme.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.language.toUpperCase(),
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    if (runnable) ...[
                      IconButton(
                        onPressed: _status == 'running' ? null : _runCode,
                        icon: Icon(
                          _status == 'running' ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
                          color: _status == 'running' ? Colors.amberAccent : Colors.greenAccent,
                          size: 18,
                        ),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tooltip: 'Запустить код',
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Код скопирован в буфер обмена'), duration: Duration(seconds: 1)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 16),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      tooltip: 'Копировать',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                widget.code.trimRight(),
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          if (_running) ...[
            Container(
              decoration: const BoxDecoration(
                color: Colors.black38,
                border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.terminal_rounded, color: VegaTheme.accent, size: 13),
                          const SizedBox(width: 6),
                          const Text(
                            'Вывод выполнения',
                            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          if (_status == 'running')
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: VegaTheme.accent),
                            ),
                        ],
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _running = false;
                            _status = 'idle';
                            _channel?.sink.close();
                          });
                        },
                        icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 14),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        tooltip: 'Закрыть вывод',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _output.join(''),
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
