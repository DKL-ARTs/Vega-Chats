import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class ProjectEditScreen extends StatefulWidget {
  final Map<String, dynamic>? projectToEdit;

  const ProjectEditScreen({super.key, this.projectToEdit});

  @override
  State<ProjectEditScreen> createState() => _ProjectEditScreenState();
}

class _ProjectEditScreenState extends State<ProjectEditScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();

  String _selectedIcon = 'folder';
  String _selectedColor = '#555555';
  List<Map<String, String>> _suggestions = [];

  bool get _isEdit => widget.projectToEdit != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.projectToEdit!;
      _nameCtrl.text = p['name'] ?? '';
      _descCtrl.text = p['description'] ?? '';
      _promptCtrl.text = p['prompt'] ?? '';
      _selectedIcon = p['iconName'] ?? 'folder';
      _selectedColor = p['iconColor'] ?? '#555555';
      
      final rawSugg = p['suggestions'] as List<dynamic>? ?? [];
      _suggestions = rawSugg.map((e) {
        if (e is Map) {
          return {
            'icon': (e['icon'] ?? '💡').toString(),
            'text': (e['text'] ?? '').toString(),
            'prompt': (e['prompt'] ?? '').toString(),
          };
        } else {
          // Fallback if suggestions were simple string list previously
          return {
            'icon': '💡',
            'text': e.toString(),
            'prompt': e.toString(),
          };
        }
      }).toList();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'folder': return Icons.folder_rounded;
      case 'money': return Icons.monetization_on_rounded;
      case 'book': return Icons.menu_book_rounded;
      case 'school': return Icons.school_rounded;
      case 'edit': return Icons.edit_rounded;
      case 'code': return Icons.code_rounded;
      case 'terminal': return Icons.terminal_rounded;
      case 'music': return Icons.music_note_rounded;
      case 'cake': return Icons.cake_rounded;
      case 'palette': return Icons.palette_rounded;
      case 'spa': return Icons.spa_rounded;
      case 'work': return Icons.work_rounded;
      case 'chart': return Icons.bar_chart_rounded;
      case 'fitness': return Icons.fitness_center_rounded;
      case 'calendar': return Icons.calendar_today_rounded;
      case 'balance': return Icons.balance_rounded;
      case 'flight': return Icons.flight_rounded;
      case 'language': return Icons.language_rounded;
      case 'pets': return Icons.pets_rounded;
      case 'science': return Icons.science_rounded;
      case 'psychology': return Icons.psychology_rounded;
      case 'flower': return Icons.local_florist_rounded;
      case 'wrench': return Icons.build_rounded;
      case 'heart': return Icons.favorite_rounded;
      case 'bug': return Icons.bug_report_rounded;
      default: return Icons.folder_open_rounded;
    }
  }

  Future<void> _showIconPickerDialog() async {
    String tempIcon = _selectedIcon;
    String tempColor = _selectedColor;

    final colors = [
      '#555555',
      '#FF4D4D',
      '#FF9F40',
      '#FFCD56',
      '#4BC080',
      '#36A2EB',
      '#9966FF',
      '#FF6384',
    ];

    final icons = [
      'folder', 'money', 'book', 'school', 'edit', 'code',
      'terminal', 'music', 'cake', 'palette', 'spa', 'work',
      'chart', 'fitness', 'calendar', 'balance', 'flight', 'language',
      'pets', 'science', 'psychology', 'flower', 'wrench', 'heart', 'bug'
    ];

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              backgroundColor: VegaTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: HexColor.fromHex(tempColor),
                      child: Icon(_getIconData(tempIcon), color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 44,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: colors.length,
                        itemBuilder: (context, idx) {
                          final colorHex = colors[idx];
                          final isSelected = colorHex == tempColor;
                          return GestureDetector(
                            onTap: () {
                              dialogSetState(() => tempColor = colorHex);
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: HexColor.fromHex(colorHex),
                                shape: BoxShape.circle,
                                border: isSelected 
                                    ? Border.all(color: Colors.white, width: 2) 
                                    : null,
                              ),
                              child: isSelected 
                                  ? const Icon(Icons.check, color: Colors.white, size: 16) 
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: icons.length,
                        itemBuilder: (context, idx) {
                          final iconName = icons[idx];
                          final isSelected = iconName == tempIcon;
                          return GestureDetector(
                            onTap: () {
                              dialogSetState(() => tempIcon = iconName);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? HexColor.fromHex(tempColor).withOpacity(0.2) 
                                    : VegaTheme.dark.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected 
                                      ? HexColor.fromHex(tempColor) 
                                      : VegaTheme.border.withOpacity(0.3),
                                  width: isSelected ? 1.5 : 0.5,
                                ),
                              ),
                              child: Icon(
                                _getIconData(iconName),
                                color: isSelected 
                                    ? HexColor.fromHex(tempColor) 
                                    : VegaTheme.textSecondary,
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx, {'icon': tempIcon, 'color': tempColor});
                  },
                  child: const Text('OK', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedIcon = result['icon']!;
        _selectedColor = result['color']!;
      });
    }
  }

  void _addSuggestion() {
    setState(() {
      _suggestions.add({'icon': '💡', 'text': '', 'prompt': ''});
    });
  }

  void _removeSuggestion(int index) {
    setState(() {
      _suggestions.removeAt(index);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final prompt = _promptCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название проекта'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final projectsJson = prefs.getString('projects_list');
    List<Map<String, dynamic>> projects = [];
    if (projectsJson != null) {
      try {
        final decoded = jsonDecode(projectsJson) as List<dynamic>;
        projects = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    final targetId = _isEdit 
        ? widget.projectToEdit!['id'] 
        : DateTime.now().millisecondsSinceEpoch.toString();

    final projectData = {
      'id': targetId,
      'name': name,
      'description': desc,
      'prompt': prompt,
      'iconName': _selectedIcon,
      'iconColor': _selectedColor,
      'suggestions': _suggestions,
    };

    if (_isEdit) {
      final index = projects.indexWhere((p) => p['id'] == targetId);
      if (index != -1) {
        projects[index] = projectData;
      }
    } else {
      projects.add(projectData);
    }

    await prefs.setString('projects_list', jsonEncode(projects));

    // Update active project details if edited project is currently active
    final activeId = prefs.getString('active_project_id') ?? 'default';
    if (activeId == targetId) {
      await prefs.setString('active_project_prompt', prompt);
    } else if (!_isEdit) {
      // Set newly created project as active
      await prefs.setString('active_project_id', targetId);
      await prefs.setString('active_project_prompt', prompt);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? 'Редактировать проект' : 'Создать проект',
          style: const TextStyle(
            color: VegaTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Сохранить', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Icon Selector preview
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _showIconPickerDialog,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: HexColor.fromHex(_selectedColor),
                        child: Icon(_getIconData(_selectedIcon), color: Colors.white, size: 38),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: VegaTheme.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Form inputs
            const Text('Название проекта', style: TextStyle(color: VegaTheme.accent, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: VegaTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VegaTheme.border, width: 0.5),
              ),
              child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Пример: Сигма ГПТ',
                  hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 18),

            const Text('Описание', style: TextStyle(color: VegaTheme.accent, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: VegaTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VegaTheme.border, width: 0.5),
              ),
              child: TextField(
                controller: _descCtrl,
                maxLines: 2,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Краткое описание назначения проекта',
                  hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 18),

            const Text('Системный промпт (инструкции для ИИ)', style: TextStyle(color: VegaTheme.accent, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: VegaTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VegaTheme.border, width: 0.5),
              ),
              child: TextField(
                controller: _promptCtrl,
                maxLines: 6,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Ты — ИИ-помощник, который...',
                  hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Suggestions header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Подсказки приветствия',
                  style: TextStyle(color: VegaTheme.accentBlue, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _addSuggestion,
                  icon: const Icon(Icons.add_rounded, size: 16, color: VegaTheme.accent),
                  label: const Text('Добавить', style: TextStyle(color: VegaTheme.accent, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_suggestions.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VegaTheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: VegaTheme.border.withOpacity(0.5), width: 0.5),
                ),
                child: const Center(
                  child: Text(
                    'Подсказки отсутствуют. Нажмите «Добавить», чтобы создать подсказки на главном экране чата.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _suggestions.length,
                itemBuilder: (context, idx) {
                  final item = _suggestions[idx];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: VegaTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VegaTheme.border, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Emoji picker textfield
                            Container(
                              width: 44,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: VegaTheme.dark.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: VegaTheme.border, width: 0.5),
                              ),
                              child: TextField(
                                style: const TextStyle(fontSize: 18, color: Colors.white),
                                textAlign: TextAlign.center,
                                controller: TextEditingController(text: item['icon'])..selection = TextSelection.collapsed(offset: (item['icon'] ?? '').length),
                                onChanged: (val) {
                                  item['icon'] = val;
                                },
                                decoration: const InputDecoration(
                                  hintText: '💡',
                                  hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 16),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Textfield for Title
                            Expanded(
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: VegaTheme.dark.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: VegaTheme.border, width: 0.5),
                                ),
                                child: TextField(
                                  style: const TextStyle(fontSize: 13, color: Colors.white),
                                  controller: TextEditingController(text: item['text'])..selection = TextSelection.collapsed(offset: (item['text'] ?? '').length),
                                  onChanged: (val) {
                                    item['text'] = val;
                                  },
                                  decoration: const InputDecoration(
                                    hintText: 'Название кнопки подсказки',
                                    hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              onPressed: () => _removeSuggestion(idx),
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Textfield for Prompt
                        Container(
                          decoration: BoxDecoration(
                            color: VegaTheme.dark.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: VegaTheme.border, width: 0.5),
                          ),
                          child: TextField(
                            maxLines: 2,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            controller: TextEditingController(text: item['prompt'])..selection = TextSelection.collapsed(offset: (item['prompt'] ?? '').length),
                            onChanged: (val) {
                              item['prompt'] = val;
                            },
                            decoration: const InputDecoration(
                              hintText: 'Текст промпта, отправляемый нейросети',
                              hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  String toHex() => '#${value.toRadixString(16).substring(2, 8).toUpperCase()}';
}
