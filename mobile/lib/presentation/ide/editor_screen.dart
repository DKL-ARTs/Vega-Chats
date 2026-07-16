import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class EditorScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const EditorScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _client = ApiClient();
  late final SyntaxHighlightingController _codeCtrl;
  bool _loading = true;
  bool _isFullscreen = false;
  
  // === SEARCH & REPLACE STATE ===
  bool _showSearchBar = false;
  final _searchQueryCtrl = TextEditingController();
  final _replaceQueryCtrl = TextEditingController();
  List<int> _searchMatchOffsets = [];
  int _currentMatchIndex = -1;
  
  Timer? _debounceTimer;
  String _saveStatus = 'saved'; // 'saved' | 'saving' | 'error'
  String _lastSavedContent = '';

  @override
  void initState() {
    super.initState();
    _codeCtrl = SyntaxHighlightingController(fileName: widget.fileName);
    _codeCtrl.addListener(_onCodeChanged);
    _searchQueryCtrl.addListener(_performSearch);
    _initAndLoad();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _codeCtrl.removeListener(_onCodeChanged);
    _searchQueryCtrl.removeListener(_performSearch);
    _codeCtrl.dispose();
    _searchQueryCtrl.dispose();
    _replaceQueryCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    _client.baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8765';
    await _loadFileContent();
  }

  Future<void> _loadFileContent() async {
    setState(() => _loading = true);
    try {
      final result = await _client.readFile(widget.filePath);
      final content = result['content'] as String? ?? '';
      _codeCtrl.text = content;
      _lastSavedContent = content;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки файла: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCodeChanged() {
    if (_codeCtrl.text == _lastSavedContent) {
      return;
    }
    setState(() {
      _saveStatus = 'saving';
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _autoSaveFile();
    });
  }

  Future<void> _autoSaveFile() async {
    final currentText = _codeCtrl.text;
    try {
      await _client.writeFile(widget.filePath, currentText);
      _lastSavedContent = currentText;
      if (mounted) {
        setState(() {
          _saveStatus = 'saved';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveStatus = 'error';
        });
      }
    }
  }

  Future<void> _saveFile() async {
    try {
      final text = _codeCtrl.text;
      await _client.writeFile(widget.filePath, text);
      _lastSavedContent = text;
      setState(() {
        _saveStatus = 'saved';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Файл успешно сохранен'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saveStatus = 'error';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _insertSymbol(String symbol) {
    final text = _codeCtrl.text;
    final selection = _codeCtrl.selection;
    
    int start = selection.start;
    int end = selection.end;
    
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, symbol);
    _codeCtrl.text = newText;
    
    // Position cursor after inserted symbol
    _codeCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: start + symbol.length),
    );
  }

  void _performSearch() {
    final query = _searchQueryCtrl.text;
    if (query.isEmpty) {
      setState(() {
        _searchMatchOffsets = [];
        _currentMatchIndex = -1;
      });
      return;
    }
    
    final text = _codeCtrl.text;
    final List<int> matches = [];
    int index = text.indexOf(query);
    while (index != -1) {
      matches.add(index);
      index = text.indexOf(query, index + query.length);
    }
    
    setState(() {
      _searchMatchOffsets = matches;
      if (matches.isNotEmpty) {
        // If current selection is not a match, default to first match
        if (_currentMatchIndex < 0 || _currentMatchIndex >= matches.length) {
          _currentMatchIndex = 0;
        }
        _selectMatch(_currentMatchIndex);
      } else {
        _currentMatchIndex = -1;
      }
    });
  }

  void _selectMatch(int matchIdx) {
    if (matchIdx < 0 || matchIdx >= _searchMatchOffsets.length) return;
    final start = _searchMatchOffsets[matchIdx];
    final end = start + _searchQueryCtrl.text.length;
    _codeCtrl.selection = TextSelection(baseOffset: start, extentOffset: end);
  }

  void _nextMatch() {
    if (_searchMatchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchMatchOffsets.length;
      _selectMatch(_currentMatchIndex);
    });
  }

  void _prevMatch() {
    if (_searchMatchOffsets.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _searchMatchOffsets.length) % _searchMatchOffsets.length;
      _selectMatch(_currentMatchIndex);
    });
  }

  void _replaceCurrent() {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _searchMatchOffsets.length) return;
    final query = _searchQueryCtrl.text;
    final replacement = _replaceQueryCtrl.text;
    final start = _searchMatchOffsets[_currentMatchIndex];
    final end = start + query.length;
    
    final text = _codeCtrl.text;
    final newText = text.replaceRange(start, end, replacement);
    _codeCtrl.text = newText;
    
    _performSearch();
  }

  void _replaceAll() {
    final query = _searchQueryCtrl.text;
    if (query.isEmpty) return;
    final replacement = _replaceQueryCtrl.text;
    final text = _codeCtrl.text;
    final newText = text.replaceAll(query, replacement);
    _codeCtrl.text = newText;
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    final quickSymbols = ['{', '}', '[', ']', '(', ')', ';', '=', '<', '>', '/', '_', ':', '"', '\''];

    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: VegaTheme.dark,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.fileName,
                        style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      _buildSaveStatusIndicator(),
                    ],
                  ),
                  Text(
                    widget.filePath.length > 35 ? '...' + widget.filePath.substring(widget.filePath.length - 35) : widget.filePath,
                    style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
                  icon: Icon(Icons.search_rounded, color: _showSearchBar ? VegaTheme.accent : Colors.white, size: 24),
                  tooltip: 'Поиск и замена',
                ),
                IconButton(
                  onPressed: () => setState(() => _isFullscreen = true),
                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 24),
                  tooltip: 'Полноэкранный режим',
                ),
                IconButton(
                  onPressed: _saveFile,
                  icon: const Icon(Icons.save_rounded, color: VegaTheme.accent, size: 24),
                  tooltip: 'Сохранить',
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VegaTheme.accent))
          : SafeArea(
              child: Column(
                children: [
                  if (_isFullscreen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0xFF0F172A),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.fileName,
                                      style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildSaveStatusIndicator(),
                                  ],
                                ),
                                Text(
                                  widget.filePath.length > 30 ? '...' + widget.filePath.substring(widget.filePath.length - 30) : widget.filePath,
                                  style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: Icon(Icons.search_rounded, color: _showSearchBar ? VegaTheme.accent : Colors.white, size: 20),
                                onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
                                tooltip: 'Поиск и замена',
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: const Icon(Icons.save_rounded, color: VegaTheme.accent, size: 20),
                                onPressed: _saveFile,
                                tooltip: 'Сохранить',
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                                icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 20),
                                onPressed: () => setState(() => _isFullscreen = false),
                                tooltip: 'Выйти из полноэкранного режима',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (_showSearchBar)
                    _buildSearchBar(),
                  Expanded(
                    child: Container(
                      margin: _isFullscreen ? const EdgeInsets.all(2) : const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A), // Slate-900 editor background
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VegaTheme.border, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left side line numbers panel (simple text builder based on lines count)
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _codeCtrl,
                            builder: (context, value, child) {
                              final lineCount = '\n'.allMatches(value.text).length + 1;
                              final numberString = List.generate(lineCount, (i) => '${i + 1}').join('\n');
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                color: const Color(0xFF1E293B), // Slate-800 line numbers BG
                                child: Text(
                                  numberString,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: VegaTheme.textSecondary.withOpacity(0.5),
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              );
                            },
                          ),
                          
                          // Code text area
                          Expanded(
                            child: TextField(
                              controller: _codeCtrl,
                              maxLines: null,
                              expands: true,
                              inputFormatters: [
                                AutoCloseBracketsFormatter(),
                              ],
                              style: const TextStyle(
                                color: Color(0xFFF1F5F9), // Slate-100 code color
                                fontFamily: 'monospace',
                                fontSize: 13,
                                height: 1.5,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                                hintText: '// Пишите код здесь...',
                                hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Quick coding symbols accessory bar above phone keyboard
                Container(
                  height: 44,
                  color: VegaTheme.surface,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: quickSymbols.length,
                    itemBuilder: (context, idx) {
                      final sym = quickSymbols[idx];
                      return GestureDetector(
                        onTap: () => _insertSymbol(sym),
                        child: Container(
                          width: 40,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          decoration: BoxDecoration(
                            color: VegaTheme.dark.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: VegaTheme.border.withOpacity(0.5), width: 0.5),
                          ),
                          child: Text(
                            sym,
                            style: const TextStyle(
                              color: VegaTheme.accent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSaveStatusIndicator() {
    Color dotColor;
    String text;
    if (_saveStatus == 'saving') {
      dotColor = Colors.orangeAccent;
      text = 'Сохранение...';
    } else if (_saveStatus == 'error') {
      dotColor = Colors.redAccent;
      text = 'Ошибка';
    } else {
      dotColor = Colors.greenAccent;
      text = 'Сохранено';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: VegaTheme.textSecondary.withOpacity(0.8), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final matchesCount = _searchMatchOffsets.length;
    final matchDisplay = matchesCount > 0 ? '${_currentMatchIndex + 1}/$matchesCount' : '0/0';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VegaTheme.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VegaTheme.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _searchQueryCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Найти...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                matchDisplay,
                style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _prevMatch,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                tooltip: 'Предыдущее совпадение',
              ),
              IconButton(
                onPressed: _nextMatch,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                tooltip: 'Следующее совпадение',
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showSearchBar = false;
                    _searchQueryCtrl.clear();
                  });
                },
                icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                tooltip: 'Закрыть поиск',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VegaTheme.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _replaceQueryCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Заменить на...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _replaceCurrent,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VegaTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Заменить', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: _replaceAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Все', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AutoCloseBracketsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;

    // 1. Step-over feature: user typed a closing char that already exists right after the cursor
    if (newText.length == oldText.length + 1) {
      final oldEnd = oldValue.selection.end;
      if (oldEnd >= 0 && oldEnd < oldText.length) {
        final insertedChar = newText[oldEnd];
        final nextChar = oldText[oldEnd];
        if ((insertedChar == '}' && nextChar == '}') ||
            (insertedChar == ']' && nextChar == ']') ||
            (insertedChar == ')' && nextChar == ')') ||
            (insertedChar == '"' && nextChar == '"') ||
            (insertedChar == "'" && nextChar == "'")) {
          // Revert the insertion and just advance cursor by 1
          return oldValue.copyWith(
            selection: TextSelection.collapsed(offset: oldEnd + 1),
          );
        }
      }
    }

    // 2. Auto-close feature: user typed an opening bracket/quote
    if (newText.length == oldText.length + 1) {
      final oldEnd = oldValue.selection.end;
      if (oldEnd >= 0 && oldEnd < newText.length) {
        final insertedChar = newText[oldEnd];
        String? closingChar;
        if (insertedChar == '{') closingChar = '}';
        else if (insertedChar == '[') closingChar = ']';
        else if (insertedChar == '(') closingChar = ')';
        else if (insertedChar == '"') closingChar = '"';
        else if (insertedChar == "'") closingChar = "'";

        if (closingChar != null) {
          final prefix = newText.substring(0, oldEnd + 1);
          final suffix = newText.substring(oldEnd + 1);
          return TextEditingValue(
            text: '$prefix$closingChar$suffix',
            selection: TextSelection.collapsed(offset: oldEnd + 1),
          );
        }
      }
    }

    return newValue;
  }
}

class SyntaxHighlightingController extends TextEditingController {
  final String fileName;

  SyntaxHighlightingController({required this.fileName, String? text}) : super(text: text);

  static final RegExp _jsDartPattern = RegExp(
    r'(//[^\n]*)|' // 1: Comments
    r'("(?:[^"\\]|\\.)*"|' // 2: Double-quoted strings
    r"'(?:[^'\\]|\\.)*')|" // 3: Single-quoted strings
    r'\b(const|let|var|function|class|return|if|else|for|while|import|export|from|new|this|await|async|void|null|true|false|final|extends|with|implements|factory|constructor|super|in|break|continue|switch|case|default|try|catch|finally|throw|rethrow|yield)\b|' // 4: Keywords
    r'\b(int|double|num|bool|String|List|Map|Set|DateTime|Future|Stream|dynamic)\b|' // 5: Types
    r'\b(\d+)\b', // 6: Numbers
  );

  static final RegExp _pyPattern = RegExp(
    r'(#[^\n]*)|' // 1: Comments
    r'("(?:[^"\\]|\\.)*"|' // 2: Double-quoted strings
    r"'(?:[^'\\]|\\.)*')|" // 3: Single-quoted strings
    r'\b(def|class|return|if|elif|else|for|while|import|from|as|in|is|and|or|not|try|except|finally|raise|print|len|range|str|int|float|list|dict|set|tuple|self|None|True|False)\b|' // 4: Keywords
    r'\b(\d+)\b', // 5: Numbers
  );

  static final RegExp _htmlPattern = RegExp(
    r'(<!--[\s\S]*?-->)|' // 1: HTML comments
    r'(<\/?[a-zA-Z0-9\-]+)|' // 2: Tag open/close name
    r'(\s[a-zA-Z0-9\-]+=)|' // 3: Attribute names
    r'("[^"]*"|' // 4: Double-quoted values
    r"'[^']*')|" // 5: Single-quoted values
    r'(>)', // 6: Tag closing bracket
  );

  static final RegExp _cssPattern = RegExp(
    r'(/\*[\s\S]*?\*/)|' // 1: Comments
    r'(\.[a-zA-Z\-0-9_]+|#[a-zA-Z\-0-9_]+|[a-zA-Z\-0-9_]+(?=\s*\{))|' // 2: Selector class, id or tag
    r'([a-zA-Z\-0-9_]+(?=\s*:))|' // 3: Property name
    r'("[^"]*"|' // 4: Strings
    r"'(?:[^'\\]|\\.)*')", // 5: Strings
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final ext = fileName.split('.').last.toLowerCase();
    RegExp pattern;
    if (ext == 'html' || ext == 'xml') {
      pattern = _htmlPattern;
    } else if (ext == 'css') {
      pattern = _cssPattern;
    } else if (ext == 'py') {
      pattern = _pyPattern;
    } else {
      pattern = _jsDartPattern;
    }

    final text = this.text;
    final matches = pattern.allMatches(text);
    if (matches.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final children = <TextSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        children.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }

      TextStyle? matchStyle;
      if (ext == 'html' || ext == 'xml') {
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null || match.group(6) != null) {
          matchStyle = const TextStyle(color: Color(0xFF7AA2F7)); // Blue tag name & brackets
        } else if (match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFFBB9AF3)); // Violet attribute name
        } else if (match.group(4) != null || match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A)); // Green string value
        }
      } else if (ext == 'css') {
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A), fontWeight: FontWeight.bold); // Green selector
        } else if (match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFF7AA2F7)); // Blue property name
        } else if (match.group(4) != null || match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFFFF9E64)); // Orange value string
        }
      } else if (ext == 'py') {
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null || match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A)); // Green string
        } else if (match.group(4) != null) {
          matchStyle = const TextStyle(color: Color(0xFFF7768E), fontWeight: FontWeight.bold); // Pink keyword
        } else if (match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFFFF9E64)); // Orange number
        }
      } else {
        // Default (JS/Dart/TS)
        if (match.group(1) != null) {
          matchStyle = const TextStyle(color: Color(0xFF6A737D), fontStyle: FontStyle.italic); // Comment
        } else if (match.group(2) != null || match.group(3) != null) {
          matchStyle = const TextStyle(color: Color(0xFF9ECE6A)); // Green string
        } else if (match.group(4) != null) {
          matchStyle = const TextStyle(color: Color(0xFFF7768E), fontWeight: FontWeight.bold); // Pink keyword
        } else if (match.group(5) != null) {
          matchStyle = const TextStyle(color: Color(0xFF7AA2F7)); // Blue type
        } else if (match.group(6) != null) {
          matchStyle = const TextStyle(color: Color(0xFFFF9E64)); // Orange number
        }
      }

      children.add(TextSpan(text: match.group(0), style: matchStyle));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      children.add(TextSpan(text: text.substring(lastIndex)));
    }

    return TextSpan(style: style, children: children);
  }
}
