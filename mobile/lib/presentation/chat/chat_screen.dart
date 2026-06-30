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
  String? _attachedFile;
  String? _attachedFileName;
  bool _attachedIsImage = false;
  String _model = 'openrouter/owl-alpha';
  int? _currentChatId;
  List<Map<String, dynamic>> _chats = [];
  Timer? _thinkingTimer;
  int _thinkingDots = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
  void dispose() {
    _controller.dispose();
    _thinkingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _model = prefs.getString('model') ?? 'openrouter/owl-alpha';
      _client.apiKey = prefs.getString('api_key') ?? '';
      _client.baseUrl = prefs.getString('base_url') ?? 'https://vega-chat-production.up.railway.app';
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
        _messages.add({
          'role': msg['role'] ?? '',
          'content': msg['content'] ?? '',
          'filePath': msg['filePath'] ?? '',
          'fileName': msg['fileName'] ?? '',
          'isImage': msg['isImage'] ?? false,
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
    if ((text.isEmpty && _attachedFile == null) || _loading) return;
    final fileToSend = _attachedFile;
    final fileNameToSend = _attachedFileName;
    final isImageToSend = _attachedIsImage;
    _controller.clear();
    FocusScope.of(context).unfocus();
    await _loadSettings();
    // Debug: show what we're sending
    String msgContent = text;
    final displayText = text.isEmpty
        ? (isImageToSend ? '📷 Photo' : '📎 ' + (fileNameToSend ?? 'File'))
        : text;
    if (_currentChatId == null) {
      _currentChatId = await ChatHistory.createChat(displayText.length > 30 ? displayText.substring(0, 30) + '...' : displayText);
    }
    await ChatHistory.addMessage(
      _currentChatId!,
      'user',
      msgContent,
      filePath: fileToSend ?? '',
      fileName: fileNameToSend ?? '',
      isImage: isImageToSend,
    );
    // Prepare files for backend
      List<Map<String, String>>? files;
      if (fileToSend != null) {
        final bytes = await File(fileToSend).readAsBytes();
        if (isImageToSend) {
          // Embed image as base64 markdown in message content
          final base64Data = base64Encode(bytes);
          final ext = fileNameToSend?.split(".").last.toLowerCase() ?? "jpg";
          final mimeType = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg");
          if (msgContent.isNotEmpty) {
            msgContent = "$msgContent\n\n![image](data:$mimeType;base64,$base64Data)";
          } else {
            msgContent = "![image](data:$mimeType;base64,$base64Data)";
          }
        } else {
          files = [{"name": fileNameToSend ?? "file", "content": base64Encode(bytes)}];
        }
      }
    
    await _loadChats();
    setState(() {
      _messages.add({'role': 'user', 'content': msgContent, 'filePath': fileToSend ?? '', 'fileName': fileNameToSend ?? '', 'isImage': isImageToSend});
      _attachedFile = null;
      _attachedFileName = null;
      _attachedIsImage = false;
      _loading = true;
    });
    _startThinking();
    try {
      final messagesForBackend = _messages.map((m) => {
        'role': m['role'].toString(),
        'content': m['content'].toString(),
      }).toList();
      setState(() => _messages.add({'role': 'assistant', 'content': ''}));
      final buffer = StringBuffer();
      await _client.streamChat(messages: messagesForBackend, model: _model, files: files,
        onChunk: (chunk) {
          if (mounted) {
            buffer.write(chunk);
            setState(() { _messages.last["content"] = buffer.toString(); });
          }
        },
        onError: (err) {
          if (mounted) setState(() { _messages.last["content"] = "Error: $err"; });
        },
      );
      _stopThinking();
      if (_currentChatId != null && _messages.isNotEmpty) {
        final lastMsg = _messages.last;
        if (lastMsg['role'] == 'assistant' && lastMsg['content'].toString().isNotEmpty) {
          await ChatHistory.addMessage(_currentChatId!, 'assistant', lastMsg['content'] ?? '');
        }
      }
    } catch (e) {
      _stopThinking();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString(), style: TextStyle(fontSize: 9)), duration: Duration(seconds: 5)));
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _regenerate(int assistantIndex) async {
    if (_loading) return;
    if (assistantIndex >= _messages.length || _messages[assistantIndex]['role'] != 'assistant') return;
    int userIndex = assistantIndex - 1;
    while (userIndex >= 0 && _messages[userIndex]['role'] != 'user') { userIndex--; }
    if (userIndex < 0) return;
    while (_messages.length > userIndex + 1) { _messages.removeLast(); }
    _stopThinking();
    setState(() { _loading = true; _messages.add({'role': 'assistant', 'content': ''}); });
    _startThinking();
    try {
      final buffer = StringBuffer();
      final msgs = _messages.sublist(0, userIndex + 1).map((m) =>
        {'role': m['role'].toString(), 'content': m['content'].toString()}).toList();
      await _client.streamChat(messages: msgs, model: _model, files: null,
        onChunk: (chunk) { if (mounted) { buffer.write(chunk); setState(() { _messages.last["content"] = buffer.toString(); }); } },
        onError: (err) { if (mounted) setState(() { _messages.last["content"] = "Error: $err"; }); });
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.isNotEmpty) {
      final savedPath = await _copyFileToAppDir(result.files.first.path!, result.files.first.name);
      setState(() { _attachedFile = savedPath; _attachedFileName = result.files.first.name; _attachedIsImage = false; });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final savedPath = await _copyFileToAppDir(image.path, image.name);
      setState(() { _attachedFile = savedPath; _attachedFileName = image.name; _attachedIsImage = true; });
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VegaTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Icons.image, color: VegaTheme.accent), title: Text('Photo'), onTap: () { Navigator.pop(ctx); _pickImage(); }),
          ListTile(leading: Icon(Icons.attach_file, color: VegaTheme.accent), title: Text('File'), onTap: () { Navigator.pop(ctx); _pickFile(); }),
        ]),
      ),
    );
  }

  void _removeAttachment() {
    setState(() { _attachedFile = null; _attachedFileName = null; _attachedIsImage = false; });
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

  Widget _buildImageWidget(Map<String, dynamic> msg) {
    final content = msg['content'] ?? '';
    if (content.contains('base64,')) {
      try {
        final base64Str = content.split('base64,')[1];
        final bytes = base64Decode(base64Str);
        return Image.memory(bytes, width: 250, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(width: 250, height: 100, color: VegaTheme.card, child: Icon(Icons.broken_image, color: VegaTheme.textSecondary)));
      } catch (_) {}
    }
    final filePath = msg['filePath'] ?? '';
    if (filePath.isNotEmpty) {
      return Image.file(File(filePath), width: 250, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(width: 250, height: 100, color: VegaTheme.card, child: Icon(Icons.broken_image, color: VegaTheme.textSecondary)));
    }
    return Container(width: 250, height: 100, color: VegaTheme.card, child: Icon(Icons.image, color: VegaTheme.textSecondary));
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
                          icon: Icon(Icons.search, color: VegaTheme.textSecondary, size: 22),
                          onPressed: () {},
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
              Expanded(
                child: _chats.isEmpty
                    ? Center(child: Text('No chats yet', style: TextStyle(color: VegaTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: _chats.length,
                        itemBuilder: (ctx, i) {
                          final chat = _chats[i];
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
                      ),
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
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu, color: VegaTheme.textSecondary),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        actions: [
          if (!_showNewChatScreen)
            IconButton(
              icon: Icon(Icons.add, color: VegaTheme.textSecondary),
              onPressed: _startNewChat,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _showNewChatScreen
                ? Center(child: Text('Start a conversation', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 16)))
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
                                // File/image preview (no border)
                                if (msg['isImage'] == true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _buildImageWidget(msg),
                                    ),
                                  ),
                                if ((msg['filePath'] ?? '').isNotEmpty && msg['isImage'] != true)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: VegaTheme.card.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 24),
                                      const SizedBox(width: 8),
                                      Text(msg['fileName'] ?? 'File', style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14)),
                                    ]),
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
                                            data: _stripImageMarkdown(msg['content'] ?? ''),
                                            selectable: true,
                                            shrinkWrap: true,
                                            styleSheet: MarkdownStyleSheet(
                                              p: const TextStyle(color: VegaTheme.textPrimary, fontSize: 15, height: 1.4),
                                              h1: const TextStyle(color: VegaTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.bold, height: 1.4),
                                              h2: const TextStyle(color: VegaTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
                                              h3: const TextStyle(color: VegaTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
                                              strong: const TextStyle(color: VegaTheme.textPrimary, fontWeight: FontWeight.bold),
                                              em: const TextStyle(color: VegaTheme.textPrimary, fontStyle: FontStyle.italic),
                                              code: TextStyle(color: VegaTheme.accent, backgroundColor: VegaTheme.surface, fontFamily: 'monospace', fontSize: 13),
                                              codeblockDecoration: BoxDecoration(color: VegaTheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: VegaTheme.border)),
                                              blockquoteDecoration: BoxDecoration(color: VegaTheme.surface, borderRadius: BorderRadius.circular(4), border: Border(left: BorderSide(color: VegaTheme.accent, width: 3))),
                                              listBullet: const TextStyle(color: VegaTheme.textPrimary, fontSize: 15),
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
          if (_attachedFile != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: VegaTheme.surface,
              child: Row(children: [
                if (_attachedIsImage)
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_attachedFile!), width: 60, height: 60, fit: BoxFit.cover))
                else
                  Container(width: 60, height: 60, decoration: BoxDecoration(color: VegaTheme.card, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 32)),
                if (!_attachedIsImage) ...[
                  const SizedBox(width: 12),
                  Expanded(child: Text(_attachedFileName ?? 'File', style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13), overflow: TextOverflow.ellipsis)),
                ] else
                  const Spacer(),
                IconButton(icon: Icon(Icons.close, color: VegaTheme.textSecondary, size: 20), onPressed: _removeAttachment),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            color: VegaTheme.dark,
            child: Row(children: [
              IconButton(icon: Icon(Icons.attach_file, color: VegaTheme.textSecondary), onPressed: _showAttachMenu),
              Expanded(child: TextField(controller: _controller, style: TextStyle(color: VegaTheme.textPrimary), decoration: InputDecoration(hintText: 'Message...', hintStyle: TextStyle(color: VegaTheme.textSecondary), filled: true, fillColor: VegaTheme.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)), onSubmitted: (_) => _send())),
              const SizedBox(width: 8),
              IconButton(onPressed: _loading ? null : _send, icon: Icon(Icons.send, color: VegaTheme.accent)),
            ]),
          ),
        ],
      ),
    );
  }
}
