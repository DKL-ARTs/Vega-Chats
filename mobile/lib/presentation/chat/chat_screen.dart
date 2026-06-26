2|import 'dart:io';
3|import 'dart:async';
4|import 'dart:convert';
5|import 'package:flutter/material.dart';
6|import 'package:flutter/services.dart';
7|import 'package:go_router/go_router.dart';
8|import 'package:shared_preferences/shared_preferences.dart';
9|import '../../core/theme.dart';
10|import '../../core/api_client.dart';
11|import '../../data/chat_history.dart';
12|import 'package:flutter_markdown/flutter_markdown.dart';
13|import 'package:path_provider/path_provider.dart';
14|import 'package:path/path.dart' as p;
15|import 'package:file_picker/file_picker.dart';
16|import 'package:image_picker/image_picker.dart';
17|
18|class ChatScreen extends StatefulWidget {
19|  final int? chatId;
20|  const ChatScreen({super.key, this.chatId});
21|  @override
22|  State<ChatScreen> createState() => _ChatScreenState();
23|}
24|
25|class _ChatScreenState extends State<ChatScreen> {
26|  final _controller = TextEditingController();
27|  final List<Map<String, dynamic>> _messages = [];
28|  final _client = ApiClient();
29|  bool _loading = false;
30|  String? _attachedFile;
31|  String? _attachedFileName;
32|  bool _attachedIsImage = false;
33|  String _model = 'openrouter/owl-alpha';
34|  int? _currentChatId;
35|  List<Map<String, dynamic>> _chats = [];
36|  Timer? _thinkingTimer;
37|  int _thinkingDots = 0;
38|  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
39|
40|  @override
41|  void initState() {
42|    super.initState();
43|    _currentChatId = widget.chatId;
44|    _loadSettings();
45|    _loadChats();
46|    if (_currentChatId != null) {
47|      _loadChat(_currentChatId!);
48|    }
49|  }
50|
51|  @override
52|  void dispose() {
53|    _controller.dispose();
54|    _thinkingTimer?.cancel();
55|    super.dispose();
56|  }
57|
58|  Future<void> _loadSettings() async {
59|    final prefs = await SharedPreferences.getInstance();
60|    setState(() {
61|      _model = prefs.getString('model') ?? 'openrouter/owl-alpha';
62|      _client.apiKey = prefs.getString('api_key') ?? '';
63|      _client.baseUrl = prefs.getString('base_url') ?? 'https://vega-chat-production.up.railway.app';
64|    });
65|  }
66|
67|  Future<void> _loadChats() async {
68|    final chats = await ChatHistory.getChats();
69|    setState(() => _chats = chats);
70|  }
71|
72|  Future<void> _loadChat(int chatId) async {
73|    final messages = await ChatHistory.getMessages(chatId);
74|    setState(() {
75|      _messages.clear();
76|      for (final msg in messages) {
77|        _messages.add({
78|          'role': msg['role'] ?? '',
79|          'content': msg['content'] ?? '',
80|          'filePath': msg['filePath'] ?? '',
81|          'fileName': msg['fileName'] ?? '',
82|          'isImage': msg['isImage'] ?? false,
83|        });
84|    });
85|  }
86|
87|  void _startThinking() {
88|    _thinkingTimer?.cancel();
89|    _thinkingDots = 0;
90|    _thinkingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
91|      if (mounted) {
92|        setState(() {
93|          _thinkingDots = (_thinkingDots + 1) % 4;
94|        });
95|    });
96|  }
97|
98|  void _stopThinking() {
99|    _thinkingTimer?.cancel();
100|    _thinkingTimer = null;
101|    _thinkingDots = 0;
102|  }
103|
104|  String get _thinkingText => 'Thinking' + '.' * _thinkingDots;
105|
106|  Future<void> _send() async {
107|    final text = _controller.text.trim();
108|    if ((text.isEmpty && _attachedFile == null) || _loading) return;
109|    final fileToSend = _attachedFile;
110|    final fileNameToSend = _attachedFileName;
111|    final isImageToSend = _attachedIsImage;
112|    _controller.clear();
113|    FocusScope.of(context).unfocus();
114|    await _loadSettings();
115|    // Debug: show what we're sending
116|    final debugKey = _client.apiKey;
117|    final debugKeyLen = debugKey.length;
118|    final debugTrimmedLen = debugKey.trim().length;
119|    final debugBytes = debugKey.codeUnits.toList();
120|    final nonAscii = debugKey.codeUnits.where((b) => b > 127 || b < 32).toList();
121|    if (mounted) {
122|      ScaffoldMessenger.of(context).showSnackBar(
123|        SnackBar(
124|          content: Text('len=$debugKeyLen trimmed=$debugTrimmedLen nonAscii=$nonAscii ALL=${debugBytes.length}bytes', style: TextStyle(fontSize: 9)),
125|          duration: Duration(seconds: 3),
126|          backgroundColor: Colors.red,
127|        ),
128|      );
129|    }
130|    final msgContent = text;
131|    final displayText = text.isEmpty
132|        ? (isImageToSend ? '📷 Photo' : '📎 ' + (fileNameToSend ?? 'File'))
133|        : text;
134|    if (_currentChatId == null) {
135|      _currentChatId = await ChatHistory.createChat(displayText.length > 30 ? displayText.substring(0, 30) + '...' : displayText);
136|    }
137|    await ChatHistory.addMessage(
138|      _currentChatId!,
139|      'user',
140|      msgContent,
141|      filePath: fileToSend ?? '',
142|      fileName: fileNameToSend ?? '',
143|      isImage: isImageToSend,
144|    );
145|    await _loadChats();
146|    setState(() {
147|      _messages.add({'role': 'user', 'content': msgContent, 'filePath': fileToSend ?? '', 'fileName': fileNameToSend ?? '', 'isImage': isImageToSend});
148|      _attachedFile = null;
149|      _attachedFileName = null;
150|      _attachedIsImage = false;
151|      _loading = true;
152|    });
153|    _startThinking();
154|    try {
155|      // Prepare files for backend
156|      List<Map<String, String>>? files;
157|      if (fileToSend != null) {
158|        final bytes = await File(fileToSend).readAsBytes();
159|        files = [{'name': fileNameToSend ?? 'file', 'content': base64Encode(bytes)}];
160|      final messagesForBackend = _messages.map((m) => {
161|        'role': m['role'].toString(),
162|        'content': m['content'].toString(),
163|      }).toList();
164|      final resp = await _client.streamChat(messages: messagesForBackend, model: _model, files: files);
      _stopThinking();
      setState(() => _messages.add({'role': 'assistant', 'content': ''}));
      final respBody = resp.body;
      if (_currentChatId != null) {
        await ChatHistory.addMessage(_currentChatId!, 'assistant', respBody);
      }
      if (mounted) setState(() { _messages.last['content'] = respBody; });
      await _loadChats();
173|    } catch (e) {
174|      _stopThinking();
175|      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString(), style: TextStyle(fontSize: 9)), duration: Duration(seconds: 5)));
176|    } finally {
177|      if (mounted) setState(() { _loading = false; });
178|    }
179|  }
180|
181|  void _copyMessage(String text) {
182|    Clipboard.setData(ClipboardData(text: text));
183|    ScaffoldMessenger.of(context).showSnackBar(
184|      SnackBar(content: Text('Copied'), duration: Duration(seconds: 1), backgroundColor: VegaTheme.surface),
185|    );
186|  }
187|
188|  void _showUserMessageMenu(BuildContext context, Map<String, dynamic> message, int index) {
189|    showModalBottomSheet(
190|      context: context,
191|      backgroundColor: VegaTheme.surface,
192|      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
193|      builder: (ctx) => SafeArea(
194|        child: Column(
195|          mainAxisSize: MainAxisSize.min,
196|          children: [
197|            ListTile(
198|              leading: Icon(Icons.edit, color: VegaTheme.accent),
199|              title: Text('Edit', style: TextStyle(color: VegaTheme.textPrimary)),
200|              onTap: () {
201|                Navigator.pop(ctx);
202|                _editMessage(index, message['content'] ?? '');
203|              },
204|            ),
205|            ListTile(
206|              leading: Icon(Icons.copy, color: VegaTheme.accent),
207|              title: Text('Copy', style: TextStyle(color: VegaTheme.textPrimary)),
208|              onTap: () {
209|                Navigator.pop(ctx);
210|                _copyMessage(message['content'] ?? '');
211|              },
212|            ),
213|          ],
214|        ),
215|      ),
216|    );
217|  }
218|
219|  void _editMessage(int index, String currentText) {
220|    _controller.text = currentText;
221|    ScaffoldMessenger.of(context).showSnackBar(
222|      SnackBar(content: Text('Edit mode - type new message'), duration: Duration(seconds: 2)),
223|    );
224|  }
225|
226|  Future<void> _deleteChat(int chatId) async {
227|    final confirmed = await showDialog<bool>(
228|      context: context,
229|      builder: (ctx) => AlertDialog(
230|        backgroundColor: VegaTheme.surface,
231|        title: Text('Delete chat?', style: TextStyle(color: VegaTheme.textPrimary)),
232|        content: Text('This action cannot be undone.', style: TextStyle(color: VegaTheme.textSecondary)),
233|        actions: [
234|          TextButton(
235|            onPressed: () => Navigator.pop(ctx, false),
236|            child: Text('Cancel', style: TextStyle(color: VegaTheme.textSecondary)),
237|          ),
238|          TextButton(
239|            onPressed: () => Navigator.pop(ctx, true),
240|            child: Text('Delete', style: TextStyle(color: Colors.red)),
241|          ),
242|        ],
243|      ),
244|    );
245|    
246|    if (confirmed == true) {
247|      await ChatHistory.deleteChat(chatId);
248|      await _loadChats();
249|      // If we deleted the current chat, go to new chat screen
250|      if (_currentChatId == chatId) {
251|        _startNewChat();
252|    }
253|  }
254|
255|  Future<String> _copyFileToAppDir(String sourcePath, String fileName) async {
256|    final appDir = await getApplicationDocumentsDirectory();
257|    final filesDir = Directory(p.join(appDir.path, 'chat_files'));
258|    if (!await filesDir.exists()) await filesDir.create(recursive: true);
259|    final ext = p.extension(fileName);
260|    final ts = DateTime.now().millisecondsSinceEpoch;
261|    final newPath = p.join(filesDir.path, '$ts$ext');
262|    await File(sourcePath).copy(newPath);
263|    return newPath;
264|  }
265|
266|  Future<void> _pickFile() async {
267|    final result = await FilePicker.platform.pickFiles(type: FileType.any);
268|    if (result != null && result.files.isNotEmpty) {
269|      final savedPath = await _copyFileToAppDir(result.files.first.path!, result.files.first.name);
270|      setState(() { _attachedFile = savedPath; _attachedFileName = result.files.first.name; _attachedIsImage = false; });
271|    }
272|  }
273|
274|  Future<void> _pickImage() async {
275|    final picker = ImagePicker();
276|    final image = await picker.pickImage(source: ImageSource.gallery);
277|    if (image != null) {
278|      final savedPath = await _copyFileToAppDir(image.path, image.name);
279|      setState(() { _attachedFile = savedPath; _attachedFileName = image.name; _attachedIsImage = true; });
280|    }
281|  }
282|
283|  void _showAttachMenu() {
284|    showModalBottomSheet(
285|      context: context,
286|      backgroundColor: VegaTheme.surface,
287|      builder: (ctx) => SafeArea(
288|        child: Column(mainAxisSize: MainAxisSize.min, children: [
289|          ListTile(leading: Icon(Icons.image, color: VegaTheme.accent), title: Text('Photo'), onTap: () { Navigator.pop(ctx); _pickImage(); }),
290|          ListTile(leading: Icon(Icons.attach_file, color: VegaTheme.accent), title: Text('File'), onTap: () { Navigator.pop(ctx); _pickFile(); }),
291|        ]),
292|      ),
293|    );
294|  }
295|
296|  void _removeAttachment() {
297|    setState(() { _attachedFile = null; _attachedFileName = null; _attachedIsImage = false; });
298|  }
299|
300|  void _startNewChat() {
301|    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
302|      _scaffoldKey.currentState?.closeDrawer();
303|    }
304|    _stopThinking();
305|    _controller.clear();
306|    setState(() {
307|      _currentChatId = null;
308|      _messages.clear();
309|      _loading = false;
310|    });
311|  }
312|
313|  void _openChat(int chatId) {
314|    _scaffoldKey.currentState?.closeDrawer();
315|    _stopThinking();
316|    setState(() {
317|      _currentChatId = chatId;
318|      _loading = false;
319|    });
320|    _loadChat(chatId);
321|  }
322|
323|  bool get _showNewChatScreen => _messages.isEmpty && !_loading;
324|
325|  @override
326|  Widget build(BuildContext context) {
327|    return Scaffold(
328|      key: _scaffoldKey,
329|      backgroundColor: VegaTheme.dark,
330|      drawer: Drawer(
331|        width: MediaQuery.of(context).size.width * 0.75,
332|        backgroundColor: VegaTheme.surface,
333|        child: SafeArea(
334|          child: Column(
335|            children: [
336|              Padding(
337|                padding: const EdgeInsets.all(16),
338|                child: Row(
339|                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
340|                  children: [
341|                    Text('Chats', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
342|                    Row(
343|                      children: [
344|                        IconButton(
345|                          icon: Icon(Icons.search, color: VegaTheme.textSecondary, size: 22),
346|                          onPressed: () {},
347|                        ),
348|                        IconButton(
349|                          icon: Icon(Icons.add, color: VegaTheme.accent),
350|                          onPressed: _startNewChat,
351|                        ),
352|                      ],
353|                    ),
354|                  ],
355|                ),
356|              ),
357|              Expanded(
358|                child: _chats.isEmpty
359|                    ? Center(child: Text('No chats yet', style: TextStyle(color: VegaTheme.textSecondary)))
360|                    : ListView.builder(
361|                        itemCount: _chats.length,
362|                        itemBuilder: (ctx, i) {
363|                          final chat = _chats[i];
364|                          final isActive = chat['id'] == _currentChatId;
365|                          return ListTile(
366|                            selected: isActive,
367|                            selectedTileColor: VegaTheme.card,
368|                            leading: Icon(Icons.chat_bubble_outline, color: isActive ? VegaTheme.accent : VegaTheme.textSecondary),
369|                            title: Text(chat['title'] ?? 'Untitled', style: TextStyle(color: isActive ? VegaTheme.accent : VegaTheme.textPrimary)),
370|                            subtitle: Text(chat['createdAt']?.toString().substring(0, 10) ?? '', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
371|                            trailing: IconButton(
372|                              icon: Icon(Icons.delete_outline, color: VegaTheme.textSecondary, size: 20),
373|                              onPressed: () => _deleteChat(chat['id']),
374|                            ),
375|                            onTap: () => _openChat(chat['id']),
376|                          );
377|                        },
378|                      ),
379|              ),
380|              Divider(color: VegaTheme.border),
381|              ListTile(
382|                leading: Icon(Icons.folder_outlined, color: VegaTheme.accent),
383|                title: Text('Files', style: TextStyle(color: VegaTheme.textPrimary)),
384|                onTap: () { _scaffoldKey.currentState?.closeDrawer(); context.push('/ide'); },
385|              ),
386|              ListTile(
387|                leading: Icon(Icons.terminal, color: VegaTheme.accent),
388|                title: Text('Terminal', style: TextStyle(color: VegaTheme.textPrimary)),
389|                onTap: () { _scaffoldKey.currentState?.closeDrawer(); context.push('/terminal'); },
390|              ),
391|              ListTile(
392|                leading: Icon(Icons.settings_outlined, color: VegaTheme.accent),
393|                title: Text('Settings', style: TextStyle(color: VegaTheme.textPrimary)),
394|                onTap: () { _scaffoldKey.currentState?.closeDrawer(); context.push('/settings'); },
395|              ),
396|              const SizedBox(height: 16),
397|            ],
398|          ),
399|        ),
400|      ),
401|      appBar: AppBar(
402|        backgroundColor: VegaTheme.dark,
403|        elevation: 0,
404|        leading: Builder(
405|          builder: (ctx) => IconButton(
406|            icon: Icon(Icons.menu, color: VegaTheme.textSecondary),
407|            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
408|          ),
409|        ),
410|        actions: [
411|          if (!_showNewChatScreen)
412|            IconButton(
413|              icon: Icon(Icons.add, color: VegaTheme.textSecondary),
414|              onPressed: _startNewChat,
415|            ),
416|        ],
417|      ),
418|      body: Column(
419|        children: [
420|          Expanded(
421|            child: _showNewChatScreen
422|                ? Center(child: Text('Start a conversation', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 16)))
423|                : ListView.builder(
424|                    padding: const EdgeInsets.all(16),
425|                    itemCount: _messages.length + (_loading ? 1 : 0),
426|                    itemBuilder: (ctx, i) {
427|                      if (_loading && i == _messages.length) {
428|                        return Align(
429|                          alignment: Alignment.centerLeft,
430|                          child: Padding(
431|                            padding: const EdgeInsets.only(bottom: 12, top: 4),
432|                            child: Text(_thinkingText, style: TextStyle(color: VegaTheme.textSecondary, fontSize: 15, fontStyle: FontStyle.italic)),
433|                          ),
434|                        );
435|                      }
436|                      if (i >= _messages.length) return const SizedBox.shrink();
437|                      final msg = _messages[i];
438|                      final isUser = msg['role'] == 'user';
439|                      return Column(
440|                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
441|                        children: [
442|                          GestureDetector(
443|                            onLongPress: () {
444|                              if (isUser) {
445|                                _showUserMessageMenu(context, msg, i);
446|                              }
447|                            },
448|                            child: Column(
449|                              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
450|                              mainAxisSize: MainAxisSize.min,
451|                              children: [
452|                                // File/image preview (no border)
453|                                if ((msg['filePath'] ?? '').isNotEmpty && msg['isImage'] == 'true')
454|                                  Container(
455|                                    margin: const EdgeInsets.only(bottom: 8),
456|                                    child: ClipRRect(
457|                                      borderRadius: BorderRadius.circular(12),
458|                                      child: Image.file(
459|                                        File(msg['filePath']!),
460|                                        width: 250,
461|                                        height: 250,
462|                                        fit: BoxFit.cover,
463|                                        errorBuilder: (_, __, ___) => Container(
464|                                          width: 250, height: 100,
465|                                          decoration: BoxDecoration(color: VegaTheme.card, borderRadius: BorderRadius.circular(12)),
466|                                          child: const Icon(Icons.broken_image, color: VegaTheme.textSecondary),
467|                                        ),
468|                                      ),
469|                                    ),
470|                                  ),
471|                                if ((msg['filePath'] ?? '').isNotEmpty && msg['isImage'] != 'true')
472|                                  Container(
473|                                    margin: const EdgeInsets.only(bottom: 8),
474|                                    padding: const EdgeInsets.all(12),
475|                                    decoration: BoxDecoration(color: VegaTheme.card.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
476|                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
477|                                      const Icon(Icons.insert_drive_file, color: VegaTheme.accent, size: 24),
478|                                      const SizedBox(width: 8),
479|                                      Text(msg['fileName'] ?? 'File', style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14)),
480|                                    ]),
481|                                  ),
482|                                // Text message
483|                                if ((msg['content'] ?? '').isNotEmpty && !(msg['content']?.startsWith('[FILE:') ?? true))
484|                                  isUser
485|                                      ? Container(
486|                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
487|                                          margin: const EdgeInsets.symmetric(horizontal: 12),
488|                                          decoration: BoxDecoration(
489|                                            color: VegaTheme.userBubble,
490|                                            borderRadius: BorderRadius.circular(12),
491|                                          ),
492|                                          child: SelectableText(msg['content'] ?? '', style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 15)),
493|                                        )
494|                                      : Padding(
495|                                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
496|                                          child: MarkdownBody(
497|                                            data: msg['content'] ?? '',
498|                                            selectable: true,
499|                                            shrinkWrap: true,
500|                                            styleSheet: MarkdownStyleSheet(
501|