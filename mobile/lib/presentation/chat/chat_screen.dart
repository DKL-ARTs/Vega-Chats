import 'dart:io';
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
    if (_currentChatId != null) {
      _loadChat(_currentChatId!);
    } else {
      _loadChats();
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
    _thinkingDots = 0;
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() => _thinkingDots = (_thinkingDots + 1) % 4);
      }
    });
  }

  void _stopThinking() {
    _thinkingTimer?.cancel();
    setState(() {
      _thinkingTimer = null;
      _thinkingDots = 0;
    });
  }

  String get _thinkingText => 'Thinking' + '.' * _thinkingDots;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachedFile == null) || _loading) return;
    final fileToSend = _attachedFile;
    final fileNameToSend = _attachedFileName;
    final isImageToSend = _attachedIsImage;

    String msgContent = text;
    List<Map<String, String>>? files;
    
    if (fileToSend != null) {
      final bytes = await File(fileToSend).readAsBytes();
      final base64Data = base64Encode(bytes);
      if (isImageToSend) {
        final ext = p.extension(fileToSend).toLowerCase().replaceAll('.', '');
        final mimeType = ext == 'png' ? 'image/png' : (ext == 'gif' ? 'image/gif' : 'image/jpeg');
        msgContent = '$text\n\n![image](data:$mimeType;base64,$base64Data)';
      } else {
        files = [{'name': fileNameToSend ?? 'file', 'content': base64Data}];
        if (text.isEmpty) msgContent = '[File: ${fileNameToSend ?? "file"}]';
      }
    }

    final displayText = text.isEmpty
        ? (isImageToSend ? '📷 Photo' : '📎 ' + (fileNameToSend ?? 'File'))
        : text;

    if (_currentChatId == null) {
      _currentChatId = await ChatHistory.createChat(displayText.length > 30 ? displayText.substring(0, 30) + '...' : displayText);
    }

    await ChatHistory.addMessage(_currentChatId!, 'user', msgContent, filePath: fileToSend ?? '', fileName: fileNameToSend ?? '', isImage: isImageToSend);
    await _loadChats();

    setState(() {
      _messages.add({'role': 'user', 'content': msgContent, 'filePath': fileToSend ?? '', 'fileName': fileNameToSend ?? '', 'isImage': isImageToSend});
      _attachedFile = null;
      _attachedFileName = null;
      _attachedIsImage = false;
      _loading = true;
    });

    _controller.clear();
    FocusScope.of(context).unfocus();
    _startThinking();

    try {
      final messagesForBackend = _messages.map((m) => {
        'role': m['role'].toString(),
        'content': m['content'].toString(),
      }).toList();
      final resp = await _client.streamChat(messages: messagesForBackend, model: _model, files: files);
      _stopThinking();
      setState(() => _messages.add({'role': 'assistant', 'content': ''}));
      String displayText = resp.isEmpty ? "EMPTY RESPONSE" : resp;
      if (mounted) setState(() { _messages.last["content"] = displayText; });
      if (_currentChatId != null) {
        await ChatHistory.addMessage(_currentChatId!, "assistant", resp);
      }
      await _loadChats();
    } catch (e) {
      _stopThinking();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), duration: const Duration(seconds: 5)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied'), duration: Duration(seconds: 1), backgroundColor: VegaTheme.surface));
  }

  void _showUserMessageMenu(BuildContext context, Map<String, dynamic> message, int index) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: Icon(Icons.copy), title: Text('Copy'), onTap: () { Navigator.pop(context); _copyMessage(message['content'] ?? ''); }),
            ListTile(leading: Icon(Icons.edit), title: Text('Edit'), onTap: () { Navigator.pop(context); _editMessage(index, message['content'] ?? ''); }),
            ListTile(leading: Icon(Icons.delete), title: Text('Delete'), onTap: () { Navigator.pop(context); _deleteChat(_currentChatId!); }),
          ],
        ),
      ),
    );
  }

  void _editMessage(int index, String currentText) {
    _controller.text = currentText;
  }

  Future<void> _deleteChat(int chatId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(title: Text('Delete chat?'), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete')),
      ]),
    );
    if (confirmed == true && _currentChatId == chatId) {
      _messages.clear();
      _currentChatId = null;
      _loading = false;
    }
  }

  Future<String> _copyFileToAppDir(String sourcePath, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final filesDir = Directory(p.join(appDir.path, 'chat_files'));
    if (!await filesDir.exists()) await filesDir.create(recursive: true);
    final ext = p.extension(fileName);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final newPath = p.join(filesDir.path, '${ts}${ext}');
    await File(sourcePath).copy(newPath);
    return newPath;
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.isNotEmpty) {
      final savedPath = await _copyFileToAppDir(result.files.first.path!, result.files.first.name);
      setState(() {
        _attachedFile = savedPath;
        _attachedFileName = result.files.first.name;
        _attachedIsImage = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final savedPath = await _copyFileToAppDir(image.path, image.name);
      setState(() {
        _attachedFile = savedPath;
        _attachedFileName = image.name;
        _attachedIsImage = true;
      });
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: Icon(Icons.photo_library), title: Text('Photo'), onTap: () { Navigator.pop(context); _pickImage(); }),
            ListTile(leading: Icon(Icons.attach_file), title: Text('File'), onTap: () { Navigator.pop(context); _pickFile(); }),
          ],
        ),
      ),
    );
  }

  void _removeAttachment() {
    setState(() { _attachedFile = null; _attachedFileName = null; _attachedIsImage = false; });
  }

  void _startNewChat() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
    setState(() {
      _messages.clear();
      _currentChatId = null;
      _loading = false;
    });
  }

  void _openChat(int chatId) {
    setState(() {
      _currentChatId = chatId;
      _loading = false;
    });
    _loadChat(chatId);
  }

  bool get _showNewChatScreen => _messages.isEmpty && !_loading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: VegaTheme.dark,
      drawer: Drawer(
        backgroundColor: VegaTheme.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: VegaTheme.dark),
              child: Text('Vega Chat', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(leading: Icon(Icons.add, color: VegaTheme.textPrimary), title: Text('New Chat', style: TextStyle(color: VegaTheme.textPrimary)), onTap: _startNewChat),
            ..._chats.map((chat) => ListTile(
              title: Text(chat['title'] ?? 'Chat', style: TextStyle(color: VegaTheme.textPrimary)),
              onTap: () => _openChat(chat['id']),
            )),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: VegaTheme.surface,
        iconTheme: IconThemeData(color: VegaTheme.textPrimary),
        title: Text('Vega Chat', style: TextStyle(color: VegaTheme.textPrimary)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _showNewChatScreen
                ? Center(child: Text('Start a conversation', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 16)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (_loading && i == _messages.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: VegaTheme.surface, borderRadius: BorderRadius.circular(12)),
                            child: Text(_thinkingText, style: TextStyle(color: VegaTheme.textSecondary)),
                          ),
                        );
                      }
                      final msg = _messages[i];
                      final isUser = msg['role'] == 'user';
                      return Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if ((msg['filePath'] ?? '').isNotEmpty && msg['isImage'] == 'true')
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  msg['filePath'] ?? '',
                                  errorBuilder: (c, e, s) => Text('[Image failed to load]', style: TextStyle(color: VegaTheme.textSecondary)),
                                ),
                              ),
                            )
                          else if ((msg['filePath'] ?? '').isNotEmpty && msg['isImage'] != 'true')
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: VegaTheme.surface, borderRadius: BorderRadius.circular(12)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.attach_file, color: VegaTheme.textSecondary, size: 16),
                                const SizedBox(width: 4),
                                Text(msg['fileName'] ?? 'File', style: TextStyle(color: VegaTheme.textSecondary)),
                              ]),
                            ),
                          if ((msg['content'] ?? '').isNotEmpty && !(msg['content']?.startsWith('[FILE:') ?? true))
                            GestureDetector(
                              onLongPress: isUser ? () => _showUserMessageMenu(context, msg, i) : null,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isUser ? VegaTheme.accent : VegaTheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: MarkdownBody(
                                  data: msg['content'] ?? '',
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(color: isUser ? Colors.white : VegaTheme.textPrimary, fontSize: 15),
                                    code: TextStyle(color: VegaTheme.accent, backgroundColor: Colors.transparent),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          if (_attachedFile != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: VegaTheme.surface,
              child: Row(
                children: [
                  if (_attachedIsImage)
                    Icon(Icons.image, color: VegaTheme.textSecondary, size: 20)
                  else
                    Icon(Icons.attach_file, color: VegaTheme.textSecondary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_attachedFileName ?? 'File', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13))),
                  IconButton(icon: Icon(Icons.close, color: VegaTheme.textSecondary, size: 18), onPressed: _removeAttachment),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            color: VegaTheme.surface,
            child: Row(
              children: [
                IconButton(icon: Icon(Icons.add, color: VegaTheme.textSecondary), onPressed: _showAttachMenu),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: VegaTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: VegaTheme.textSecondary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: VegaTheme.dark,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(_loading ? Icons.hourglass_top : Icons.send, color: VegaTheme.accent),
                  onPressed: _loading ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
