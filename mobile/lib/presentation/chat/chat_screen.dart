import "dart:io";
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../data/chat_history.dart';

class ChatScreen extends StatefulWidget {
  final int? chatId;
  const ChatScreen({super.key, this.chatId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final _client = ApiClient();
  bool _loading = false;
  String _model = 'owl-alpha';
  int? _currentChatId;
  List<Map<String, dynamic>> _chats = [];
  Timer? _thinkingTimer;
  int _thinkingDots = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _attachedFile;
  String? _attachedFileName;
  bool _attachedIsImage = false;

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
      _model = prefs.getString('model') ?? 'owl-alpha';
      _client.apiKey = prefs.getString('api_key') ?? '';
      _client.baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8765';
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
          'role': msg['role'],
          'content': msg['content'],
          'filePath': msg['filePath'] ?? '',
          'fileName': msg['fileName'] ?? '',
          'isImage': msg['isImage'] ?? 'false',
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


  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _attachedFile = result.files.first.path;
        _attachedFileName = result.files.first.name;
        _attachedIsImage = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _attachedFile = image.path;
        _attachedFileName = image.name;
        _attachedIsImage = true;
      });
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VegaTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.image, color: VegaTheme.accent),
              title: Text('Photo', style: TextStyle(color: VegaTheme.textPrimary)),
              onTap: () { Navigator.pop(ctx); _pickImage(); },
            ),
            ListTile(
              leading: Icon(Icons.attach_file, color: VegaTheme.accent),
              title: Text('File', style: TextStyle(color: VegaTheme.textPrimary)),
              onTap: () { Navigator.pop(ctx); _pickFile(); },
            ),
          ],
        ),
      ),
    );
  }

  void _removeAttachment() {
    setState(() { _attachedFile = null; _attachedFileName = null; _attachedIsImage = false; });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachedFile == null) || _loading) return;
    _controller.clear();
    FocusScope.of(context).unfocus();
    await _loadSettings();
    if (_currentChatId == null) {
      _currentChatId = await ChatHistory.createChat(
        _attachedFile != null ? 'File: $_attachedFileName' : (text.length > 30 ? text.substring(0, 30) + '...' : text)
      );
    }
    
    // Build message content
    String messageContent = text.isEmpty ? '' : text;
    
    await ChatHistory.addMessage(_currentChatId!, 'user', messageContent);
    setState(() {
      _messages.add({'role': 'user', 'content': messageContent, 'filePath': _attachedFile ?? '', 'fileName': _attachedFileName ?? '', 'isImage': _attachedIsImage ? 'true' : 'false'});
      _loading = true;
    });
    
    final fileToSend = _attachedFile;
    final fileName = _attachedFileName;
    final isImage = _attachedIsImage;
    _removeAttachment();
    
    _startThinking();
    try {
      // Prepare files for backend
      List<Map<String, String>>? files;
      if (fileToSend != null) {
        final bytes = await File(fileToSend).readAsBytes();
        files = [{'name': fileName ?? 'file', 'content': base64Encode(bytes)}];
      }
      
      final resp = await _client.streamChat(messages: _messages, model: _model, files: files);
      _stopThinking();
      setState(() => _messages.add({'role': 'assistant', 'content': ''}));
      String currentMessage = '';
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') break;
            currentMessage += data;
            setState(() { _messages.last['content'] = currentMessage; });
          }
        }
      }
      if (_currentChatId != null) {
        await ChatHistory.addMessage(_currentChatId!, 'assistant', currentMessage);
      }
      await _loadChats();
    } catch (e) {
      _stopThinking();
      setState(() { _messages.add({'role': 'assistant', 'content': 'Error: $e'}); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied'), duration: Duration(seconds: 1), backgroundColor: VegaTheme.surface),
    );
  }

  void _showUserMessageMenu(BuildContext context, Map<String, String> message, int index) {
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
                : ListView.builder(
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
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.8),
                              decoration: BoxDecoration(
                                color: isUser ? VegaTheme.userBubble : VegaTheme.assistantBubble,
                                borderRadius: BorderRadius.circular(12),
                                border: null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (msg['filePath']?.isNotEmpty == true && msg['isImage'] == 'true')
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(msg['filePath']!),
                                        width: 200,
                                        height: 200,
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx, err, stack) => Container(
                                          width: 200,
                                          height: 100,
                                          color: VegaTheme.card,
                                          child: Icon(Icons.broken_image, color: VegaTheme.textSecondary),
                                        ),
                                      ),
                                    ),
                                  if (msg['filePath']?.isNotEmpty == true && msg['isImage'] != 'true')
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 20),
                                        const SizedBox(width: 6),
                                        Text(msg['fileName'] ?? 'File', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                      ],
                                    ),
                                  if (msg['content']?.isNotEmpty == true && !(msg['content']?.startsWith('[FILE:') ?? false))
                                    Padding(
                                      padding: EdgeInsets.only(top: (msg['filePath']?.isNotEmpty == true) ? 8 : 0),
                                      child: Text(msg['content'] ?? '', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 15)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (!isUser && msg['content']?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12, left: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => _copyMessage(msg['content'] ?? ''),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(Icons.copy, size: 16, color: VegaTheme.textSecondary),
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
          // Attachment preview
          if (_attachedFile != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: VegaTheme.surface,
              child: Row(children: [
                if (_attachedIsImage)
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_attachedFile!), width: 80, height: 80, fit: BoxFit.cover))
                else
                  Container(width: 80, height: 80, decoration: BoxDecoration(color: VegaTheme.card, borderRadius: BorderRadius.circular(8)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 32), const SizedBox(height: 4), Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(_attachedFileName ?? 'File', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 10), overflow: TextOverflow.ellipsis, maxLines: 1))])),
                const Spacer(),
                IconButton(icon: Icon(Icons.close, color: VegaTheme.textSecondary, size: 20), onPressed: _removeAttachment),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            color: VegaTheme.dark,
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.attach_file, color: _attachedFile != null ? VegaTheme.accent : VegaTheme.textSecondary),
                onPressed: _showAttachMenu,
              ),
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
