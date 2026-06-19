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
      try {
        final result = await _client.readFile(_currentPath + '/' + item['name']);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: VegaTheme.surface,
              title: Text(item['name'], style: TextStyle(color: VegaTheme.textPrimary)),
              content: SingleChildScrollView(
                child: Text(
                  result['content'] ?? '',
                  style: TextStyle(color: VegaTheme.textSecondary, fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: TextStyle(color: VegaTheme.accent)),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
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
