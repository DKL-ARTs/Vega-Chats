import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class IdeScreen extends StatefulWidget {
  const IdeScreen({super.key});
  @override
  State<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends State<IdeScreen> {
  final _client = ApiClient();
  String _currentPath = '/root/workspace';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final result = await _client.listFiles(_currentPath);
      setState(() => _items = List<Map<String, dynamic>>.from(result['items'] ?? []));
    } catch (e) {
      setState(() => _items = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    if (item['is_dir'] == true) {
      setState(() => _currentPath = _currentPath + '/' + item['name']);
      await _loadFiles();
    } else {
      _openFileEditor(_currentPath + '/' + item['name'], item['name']);
    }
  }

  void _openFileEditor(String path, String name) async {
    try {
      final result = await _client.readFile(path);
      final controller = TextEditingController(text: result['content'] ?? '');
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: VegaTheme.surface,
          title: Row(
            children: [
              Expanded(child: Text(name, style: TextStyle(color: VegaTheme.textPrimary, fontSize: 14))),
              IconButton(
                icon: Icon(Icons.save, color: VegaTheme.accent, size: 20),
                onPressed: () async {
                  await _client.writeFile(path, controller.text);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          content: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: TextStyle(color: VegaTheme.textPrimary, fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Start typing...',
              hintStyle: TextStyle(color: VegaTheme.textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: TextStyle(color: VegaTheme.textSecondary)),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _createNewFile() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        title: Text('New file', style: TextStyle(color: VegaTheme.textPrimary)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: VegaTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'filename.txt',
            hintStyle: TextStyle(color: VegaTheme.textSecondary),
            border: OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                _openFileEditor(_currentPath + '/' + name, name);
              }
            },
            child: Text('Create', style: TextStyle(color: VegaTheme.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('Files', style: TextStyle(color: VegaTheme.textPrimary)),
        leading: _currentPath != '/root/workspace'
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: VegaTheme.textSecondary),
                onPressed: () {
                  final parts = _currentPath.split('/');
                  parts.removeLast();
                  setState(() => _currentPath = parts.join('/'));
                  _loadFiles();
                },
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: VegaTheme.textSecondary),
            onPressed: _createNewFile,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: VegaTheme.accent))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (ctx, i) {
                final item = _items[i];
                return ListTile(
                  leading: Icon(
                    item['is_dir'] == true ? Icons.folder : Icons.insert_drive_file,
                    color: item['is_dir'] == true ? VegaTheme.accent : VegaTheme.textSecondary,
                  ),
                  title: Text(
                    item['name'],
                    style: TextStyle(color: VegaTheme.textPrimary),
                  ),
                  trailing: item['is_dir'] == true
                      ? Icon(Icons.chevron_right, color: VegaTheme.textSecondary)
                      : Text(
                          item['size'].toString() + ' B',
                          style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
                        ),
                  onTap: () => _openItem(item),
                );
              },
            ),
    );
  }
}
