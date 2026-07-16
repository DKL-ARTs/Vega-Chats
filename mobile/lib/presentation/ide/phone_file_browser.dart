import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import '../../core/theme.dart';
import '../../core/api_client.dart';

class PhoneFileBrowser extends StatefulWidget {
  final ApiClient client;
  final Function(String filePath, String fileName, String content)? onOpenInEditor;
  final Function(String actionType, String filePath, String fileName)? onAiAction;

  const PhoneFileBrowser({
    super.key,
    required this.client,
    this.onOpenInEditor,
    this.onAiAction,
  });

  @override
  State<PhoneFileBrowser> createState() => _PhoneFileBrowserState();
}

class _PhoneFileBrowserState extends State<PhoneFileBrowser> {
  String _currentPath = '/storage/emulated/0';
  List<FileSystemEntity> _entries = [];
  bool _loading = true;
  bool _permissionGranted = false;
  String _fileSearchQuery = '';
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    setState(() => _loading = true);
    
    bool granted = false;

    if (Platform.isAndroid) {
      // Android 11+ requires MANAGE_EXTERNAL_STORAGE
      if (await Permission.manageExternalStorage.isGranted) {
        granted = true;
      } else {
        // Try legacy storage permission first
        final legacyStatus = await Permission.storage.request();
        if (legacyStatus.isGranted) {
          granted = true;
        } else {
          // Request full storage access for Android 11+
          final manageStatus = await Permission.manageExternalStorage.request();
          granted = manageStatus.isGranted;
        }
      }
    } else {
      granted = true;
    }

    setState(() {
      _permissionGranted = granted;
    });

    if (granted) {
      await _loadDir(_currentPath);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadDir(String path) async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final dir = Directory(path);
      final List<FileSystemEntity> entries = [];
      
      await for (final entity in dir.list(followLinks: false)) {
        entries.add(entity);
      }

      // Sort: folders first, then files, both alphabetically
      entries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      setState(() {
        _currentPath = path;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = 'Нет доступа к папке: $e';
        _loading = false;
      });
    }
  }

  void _navigateUp() {
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath) {
      _loadDir(parent);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  String _getFileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.dart': return '🎯';
      case '.py': return '🐍';
      case '.js': case '.ts': return '📜';
      case '.html': case '.htm': return '🌐';
      case '.css': return '🎨';
      case '.json': return '📋';
      case '.md': return '📝';
      case '.txt': return '📄';
      case '.jpg': case '.jpeg': case '.png': case '.gif': case '.webp': case '.bmp': return '🖼️';
      case '.mp4': case '.mkv': case '.avi': case '.mov': return '🎬';
      case '.mp3': case '.wav': case '.ogg': case '.aac': return '🎵';
      case '.pdf': return '📕';
      case '.zip': case '.tar': case '.gz': case '.rar': return '📦';
      case '.apk': return '📱';
      case '.sh': return '⚙️';
      case '.xml': return '🔖';
      default: return '📄';
    }
  }

  bool _isTextFile(String name) {
    final ext = p.extension(name).toLowerCase();
    return [
      '.dart', '.py', '.js', '.ts', '.html', '.htm', '.css', '.json',
      '.md', '.txt', '.sh', '.xml', '.yaml', '.yml', '.toml', '.ini',
      '.conf', '.cfg', '.log', '.csv', '.swift', '.kt', '.java', '.c',
      '.cpp', '.h', '.go', '.rs', '.rb', '.php', '.sql', '.gradle',
    ].contains(ext);
  }

  Future<void> _openFile(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    if (!_isTextFile(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Бинарные файлы не поддерживаются для редактирования'),
          backgroundColor: VegaTheme.surface,
        ),
      );
      return;
    }

    try {
      final content = await File(entity.path).readAsString();
      if (widget.onOpenInEditor != null) {
        widget.onOpenInEditor!(entity.path, name, content);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть файл: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _copyToServer(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    try {
      final content = await File(entity.path).readAsString();
      await widget.client.writeFile('/root/workspace/$name', content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_upload_rounded, color: Colors.greenAccent, size: 18),
                const SizedBox(width: 8),
                Text('Файл "$name" скопирован на сервер'),
              ],
            ),
            backgroundColor: VegaTheme.surface,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _copyPathToClipboard(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Путь скопирован в буфер'), duration: Duration(seconds: 1)),
      );
    }
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Icon(Icons.folder_off_rounded, color: Colors.orange, size: 56),
            ),
            const SizedBox(height: 20),
            const Text(
              'Нет доступа к файлам',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Для просмотра файлов телефона нужно разрешение на доступ к хранилищу',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await openAppSettings();
                // Retry after returning from settings
                await _checkPermissionAndLoad();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: VegaTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Открыть настройки'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _checkPermissionAndLoad,
              child: const Text('Повторить попытку', style: TextStyle(color: VegaTheme.accent)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionGranted && !_loading) {
      return _buildPermissionDenied();
    }

    final filteredEntries = _entries.where((e) {
      final name = p.basename(e.path).toLowerCase();
      return name.contains(_fileSearchQuery.toLowerCase());
    }).toList();

    // Breadcrumb path
    final pathParts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    
    return Column(
      children: [
        // Breadcrumb navigation
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _loadDir('/storage/emulated/0'),
                child: const Icon(Icons.phone_android_rounded, color: VegaTheme.accent, size: 18),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: pathParts.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final part = entry.value;
                      final fullPath = '/' + pathParts.sublist(0, idx + 1).join('/');
                      final isLast = idx == pathParts.length - 1;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(' / ', style: TextStyle(color: Colors.white24, fontSize: 11)),
                          GestureDetector(
                            onTap: isLast ? null : () => _loadDir(fullPath),
                            child: Text(
                              part,
                              style: TextStyle(
                                color: isLast ? Colors.white : VegaTheme.accent,
                                fontSize: 11,
                                fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_currentPath != '/')
                GestureDetector(
                  onTap: _navigateUp,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text('↑ Назад', style: TextStyle(color: VegaTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),

        // Search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      hintText: 'Поиск в папке...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) => setState(() => _fileSearchQuery = val),
                  ),
                ),
                if (_fileSearchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _fileSearchQuery = ''),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // File list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: VegaTheme.accent))
              : _errorMsg != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline_rounded, color: Colors.orange, size: 40),
                          const SizedBox(height: 12),
                          Text(_errorMsg!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _navigateUp,
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: const Text('Назад'),
                            style: TextButton.styleFrom(foregroundColor: VegaTheme.accent),
                          ),
                        ],
                      ),
                    ))
                  : filteredEntries.isEmpty
                      ? const Center(child: Text('Папка пуста', style: TextStyle(color: Colors.white38, fontSize: 13)))
                      : ListView.builder(
                          itemCount: filteredEntries.length,
                          itemBuilder: (ctx, i) {
                            final entity = filteredEntries[i];
                            final name = p.basename(entity.path);
                            final isDir = entity is Directory;
                            
                            String? sizeLabel;
                            if (!isDir) {
                              try {
                                final stat = entity.statSync();
                                sizeLabel = _formatSize(stat.size);
                              } catch (_) {}
                            }

                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              leading: isDir
                                  ? const Icon(Icons.folder_rounded, color: VegaTheme.accent, size: 22)
                                  : Text(_getFileIcon(name), style: const TextStyle(fontSize: 18)),
                              title: Text(
                                name,
                                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: sizeLabel != null
                                  ? Text(sizeLabel, style: const TextStyle(color: Colors.white38, fontSize: 10))
                                  : null,
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 18),
                                color: VegaTheme.surface,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (value) async {
                                  switch (value) {
                                    case 'copy_path':
                                      await _copyPathToClipboard(entity.path);
                                      break;
                                    case 'copy_to_server':
                                      if (!isDir) await _copyToServer(entity);
                                      break;
                                    case 'open_editor':
                                      if (!isDir) await _openFile(entity);
                                      break;
                                    case 'ai_explain':
                                    case 'ai_tests':
                                    case 'ai_refactor':
                                    case 'ai_bugs':
                                      if (widget.onAiAction != null) {
                                        widget.onAiAction!(value.substring(3), entity.path, name);
                                      }
                                      break;
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'copy_path',
                                    child: Row(children: [
                                      Icon(Icons.link_rounded, color: VegaTheme.textPrimary, size: 16),
                                      SizedBox(width: 8),
                                      Text('Копировать путь', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                    ]),
                                  ),
                                  if (!isDir) ...[
                                    const PopupMenuItem(
                                      value: 'open_editor',
                                      child: Row(children: [
                                        Icon(Icons.edit_rounded, color: VegaTheme.textPrimary, size: 16),
                                        SizedBox(width: 8),
                                        Text('Открыть в редакторе', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'copy_to_server',
                                      child: Row(children: [
                                        Icon(Icons.cloud_upload_rounded, color: Colors.greenAccent, size: 16),
                                        SizedBox(width: 8),
                                        Text('Копировать на сервер', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(
                                      value: 'ai_explain',
                                      child: Row(children: [
                                        Icon(Icons.psychology_rounded, color: Colors.amberAccent, size: 16),
                                        SizedBox(width: 8),
                                        Text('Объяснить код', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'ai_tests',
                                      child: Row(children: [
                                        Icon(Icons.science_rounded, color: Colors.amberAccent, size: 16),
                                        SizedBox(width: 8),
                                        Text('Написать тесты', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'ai_refactor',
                                      child: Row(children: [
                                        Icon(Icons.build_circle_rounded, color: Colors.amberAccent, size: 16),
                                        SizedBox(width: 8),
                                        Text('Рефакторинг', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'ai_bugs',
                                      child: Row(children: [
                                        Icon(Icons.bug_report_rounded, color: Colors.amberAccent, size: 16),
                                        SizedBox(width: 8),
                                        Text('Найти баги', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                      ]),
                                    ),
                                  ],
                                ],
                              ),
                              onTap: () {
                                if (isDir) {
                                  _loadDir(entity.path);
                                } else {
                                  _openFile(entity);
                                }
                              },
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
