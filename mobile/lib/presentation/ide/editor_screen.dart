import 'package:flutter/material.dart';
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
  final _codeCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFileContent();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFileContent() async {
    setState(() => _loading = true);
    try {
      final result = await _client.readFile(widget.filePath);
      _codeCtrl.text = result['content'] ?? '';
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки файла: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveFile() async {
    try {
      await _client.writeFile(widget.filePath, _codeCtrl.text);
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

  @override
  Widget build(BuildContext context) {
    final quickSymbols = ['{', '}', '[', ']', '(', ')', ';', '=', '<', '>', '/', '_', ':', '"', '\''];

    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.filePath.length > 35 ? '...' + widget.filePath.substring(widget.filePath.length - 35) : widget.filePath,
              style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _saveFile,
            icon: const Icon(Icons.save_rounded, color: VegaTheme.accent, size: 24),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VegaTheme.accent))
          : Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(12),
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
    );
  }
}
