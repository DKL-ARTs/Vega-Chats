import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, dynamic>> _projects = [];
  String _activeProjectId = 'default';

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projectsJson = prefs.getString('projects_list');
    
    List<Map<String, dynamic>> loadedProjects = [];
    if (projectsJson != null) {
      try {
        final decoded = jsonDecode(projectsJson) as List<dynamic>;
        loadedProjects = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint('Error decoding projects: $e');
      }
    }
    
    if (loadedProjects.isEmpty) {
      loadedProjects = [
        {
          'id': 'default',
          'name': 'Общий помощник',
          'description': 'Универсальный ИИ-помощник без специфичных системных инструкций.',
          'prompt': 'Ты — полезный, дружелюбный и умный ИИ-ассистент.'
        },
        {
          'id': 'flutter',
          'name': 'Flutter-разработчик',
          'description': 'Создание и отладка мобильных приложений на Flutter/Dart.',
          'prompt': 'Ты — эксперт по разработке мобильных приложений на Flutter и Dart. Пиши чистый, оптимизированный код, следуй правилам чистой архитектуры.'
        },
        {
          'id': 'python',
          'name': 'Python-разработчик',
          'description': 'Разработка скриптов автоматизации, бэкенда на FastAPI, Django и парсеров.',
          'prompt': 'Ты — опытный Senior Python разработчик. Пиши чистый, питоничный код (PEP 8), помогай писать автоматизацию и веб-приложения на FastAPI/Django.'
        },
        {
          'id': 'qa',
          'name': 'Тестировщик кода',
          'description': 'Анализ багов, написание unit-тестов и проверка алгоритмов.',
          'prompt': 'Ты — QA инженер. Помогай писать Unit-тесты, искать логические ошибки и граничные случаи в предоставленном коде.'
        }
      ];
      await prefs.setString('projects_list', jsonEncode(loadedProjects));
    }

    final activeId = prefs.getString('active_project_id') ?? 'default';

    setState(() {
      _projects = loadedProjects;
      _activeProjectId = activeId;
    });
  }

  Future<void> _selectProject(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_project_id', id);
    // Find prompt of selected project
    final activeProj = _projects.firstWhere((p) => p['id'] == id, orElse: () => _projects.first);
    await prefs.setString('active_project_prompt', activeProj['prompt'] ?? '');
    setState(() {
      _activeProjectId = id;
    });
    if (mounted) {
      Navigator.pop(context, true); // Return true to trigger reload in chat
    }
  }

  Future<void> _createProject(String name, String description, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final newProj = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'description': description,
      'prompt': prompt,
    };
    setState(() {
      _projects.add(newProj);
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    await _selectProject(newProj['id']!);
  }

  Future<void> _deleteProject(String id) async {
    if (id == 'default') return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _projects.removeWhere((p) => p['id'] == id);
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    if (_activeProjectId == id) {
      await _selectProject('default');
    } else {
      _loadProjects();
    }
  }

  Future<void> _editProject(String id, String name, String description, String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final index = _projects.indexWhere((p) => p['id'] == id);
      if (index != -1) {
        _projects[index] = {
          'id': id,
          'name': name,
          'description': description,
          'prompt': prompt,
        };
      }
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    if (_activeProjectId == id) {
      await prefs.setString('active_project_prompt', prompt);
    }
    _loadProjects();
  }

  void _showCreateProjectDialog({Map<String, dynamic>? projectToEdit}) {
    final isEdit = projectToEdit != null;
    final nameCtrl = TextEditingController(text: isEdit ? projectToEdit['name'] : '');
    final descCtrl = TextEditingController(text: isEdit ? projectToEdit['description'] : '');
    final promptCtrl = TextEditingController(text: isEdit ? projectToEdit['prompt'] : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEdit ? 'Редактировать проект' : 'Создать проект',
          style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Название проекта',
                  labelStyle: TextStyle(color: VegaTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Описание для себя',
                  labelStyle: TextStyle(color: VegaTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: promptCtrl,
                maxLines: 4,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Системный промпт / Инструкции ИИ',
                  labelStyle: TextStyle(color: VegaTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
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
              final name = nameCtrl.text.trim();
              final desc = descCtrl.text.trim();
              final prompt = promptCtrl.text.trim();
              if (name.isNotEmpty) {
                if (isEdit) {
                  _editProject(projectToEdit['id']!, name, desc, prompt);
                } else {
                  _createProject(name, desc, prompt);
                }
                Navigator.pop(ctx);
              }
            },
            child: Text(isEdit ? 'Сохранить' : 'Создать', style: const TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customProjects = _projects.where((p) => p['id'] != 'default').toList();
    final isDefaultActive = _activeProjectId == 'default';

    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: const Text(
          'Проекты',
          style: TextStyle(
            color: VegaTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: VegaTheme.accent, size: 28),
            onPressed: () => _showCreateProjectDialog(),
          ),
        ],
      ),
      body: _projects.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: customProjects.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDefaultActive ? VegaTheme.accent.withOpacity(0.05) : VegaTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDefaultActive ? VegaTheme.accent : VegaTheme.border,
                        width: isDefaultActive ? 1.5 : 0.5,
                      ),
                      boxShadow: isDefaultActive
                          ? [
                              BoxShadow(
                                color: VegaTheme.accent.withOpacity(0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : [],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: isDefaultActive ? VegaTheme.accent : VegaTheme.textSecondary,
                        size: 26,
                      ),
                      title: const Text(
                        'Обычный чат (Без проекта)',
                        style: TextStyle(
                          color: VegaTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Использование ИИ-ассистента по умолчанию без применения инструкций конкретных проектов.',
                        style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
                      ),
                      trailing: isDefaultActive
                          ? const Icon(Icons.check_circle_rounded, color: VegaTheme.accent, size: 24)
                          : ElevatedButton(
                              onPressed: () => _selectProject('default'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: VegaTheme.accent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              child: const Text('Выбрать'),
                            ),
                      onTap: isDefaultActive ? null : () => _selectProject('default'),
                    ),
                  );
                }

                final proj = customProjects[index - 1];
                final isCurrent = proj['id'] == _activeProjectId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: VegaTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isCurrent ? VegaTheme.accent : VegaTheme.border,
                      width: isCurrent ? 1.5 : 0.5,
                    ),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: VegaTheme.accent.withOpacity(0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ExpansionTile(
                      backgroundColor: Colors.transparent,
                      collapsedBackgroundColor: Colors.transparent,
                      shape: const Border(),
                      leading: Icon(
                        isCurrent ? Icons.folder_shared_rounded : Icons.folder_open_rounded,
                        color: isCurrent ? VegaTheme.accent : VegaTheme.textSecondary,
                        size: 26,
                      ),
                      title: Text(
                        proj['name'] ?? '',
                        style: TextStyle(
                          color: isCurrent ? VegaTheme.accent : VegaTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        proj['description'] ?? 'Без описания',
                        style: const TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(color: VegaTheme.border),
                              const SizedBox(height: 4),
                              const Text(
                                'Системный промпт:',
                                style: TextStyle(color: VegaTheme.accentBlue, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: VegaTheme.dark,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: VegaTheme.border, width: 0.5),
                                ),
                                child: Text(
                                  proj['prompt'] ?? 'Промпт не задан',
                                  style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: VegaTheme.textSecondary),
                                    onPressed: () => _showCreateProjectDialog(projectToEdit: proj),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _deleteProject(proj['id']!),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: isCurrent ? null : () => _selectProject(proj['id']!),
                                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                    label: Text(isCurrent ? 'Выбран' : 'Выбрать'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: VegaTheme.accent,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: VegaTheme.border,
                                      disabledForegroundColor: VegaTheme.textSecondary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
