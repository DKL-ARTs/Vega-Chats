import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../data/chat_history.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, dynamic>> _projects = [];
  String _activeProjectId = 'default';
  List<Map<String, dynamic>> _allChats = [];

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
          'description': 'Проектирование архитектуры и написание кода мобильных приложений на Dart.',
          'prompt': 'Ты — эксперт по разработке мобильных приложений на Flutter и Dart. Пиши чистый, оптимизированный код, следуй правилам чистой архитектуры.'
        },
        {
          'id': 'python',
          'name': 'Python-разработчик',
          'description': 'Автоматизация задач, парсинг сайтов, разработка бэкенда на FastAPI/Django и работа с данными.',
          'prompt': 'Ты — опытный Senior Python разработчик. Пиши чистый, питоничный код (PEP 8), помогай писать автоматизацию и веб-приложения на FastAPI/Django.'
        },
        {
          'id': 'qa',
          'name': 'Тестировщик кода (QA)',
          'description': 'Написание Unit-тестов, поиск логических ошибок, багов и проверка граничных условий.',
          'prompt': 'Ты — QA инженер. Помогай писать Unit-тесты, искать логические ошибки и граничные случаи в предоставленном коде.'
        },
        {
          'id': 'chef',
          'name': 'Шеф-повар кулинарии',
          'description': 'Подбор рецептов по ингредиентам, кулинарные советы и составление здорового меню.',
          'prompt': 'Ты — профессиональный кулинарный шеф-повар. Помогай пользователю придумывать аппетитные рецепты из имеющихся продуктов, давай советы по технике приготовления, замене ингредиентов и красивой подаче блюд.'
        },
        {
          'id': 'english',
          'name': 'Репетитор английского',
          'description': 'Практика общения, перевод, грамматика и мягкое исправление ошибок.',
          'prompt': 'Ты — дружелюбный и поддерживающий репетитор английского языка. Помогай пользователю изучать язык: отвечай на английском, переводи предложения, понятно объясняй правила грамматики и исправляй ошибки в сообщениях пользователя.'
        },
        {
          'id': 'copywriter',
          'name': 'Креативный копирайтер',
          'description': 'Создание текстов для постов, сценариев, статей, писем и праздничных поздравлений.',
          'prompt': 'Ты — талантливый копирайтер и креативный писатель. Твоя задача — создавать вовлекающие и качественные тексты, посты для соцсетей, сценарии, статьи и стихи в различных тонах речи (официальный, дружелюбный, юмористический) по запросу пользователя.'
        },
        {
          'id': 'fitness',
          'name': 'Фитнес-тренер и нутрициолог',
          'description': 'Составление безопасных тренировочных программ для дома/зала и расчет здорового рациона.',
          'prompt': 'Ты — опытный персональный фитнес-тренер и нутрициолог. Составляй безопасные и эффективные планы тренировок для дома или зала, давай рекомендации по расчету КБЖУ, питьевому режиму и здоровому образу жизни.'
        }
      ];
      await prefs.setString('projects_list', jsonEncode(loadedProjects));
    }

    final List<Map<String, dynamic>> defaultList = [
      {
        'id': 'default',
        'name': 'Общий помощник',
        'description': 'Универсальный ИИ-помощник без специфичных системных инструкций.',
        'prompt': 'Ты — полезный, дружелюбный и умный ИИ-ассистент.'
      },
      {
        'id': 'flutter',
        'name': 'Flutter-разработчик',
        'description': 'Проектирование архитектуры и написание кода мобильных приложений на Dart.',
        'prompt': 'Ты — эксперт по разработке мобильных приложений на Flutter и Dart. Пиши чистый, оптимизированный код, следуй правилам чистой архитектуры.'
      },
      {
        'id': 'python',
        'name': 'Python-разработчик',
        'description': 'Автоматизация задач, парсинг сайтов, разработка бэкенда на FastAPI/Django и работа с данными.',
        'prompt': 'Ты — опытный Senior Python разработчик. Пиши чистый, питоничный код (PEP 8), помогай писать автоматизацию и веб-приложения на FastAPI/Django.'
      },
      {
        'id': 'qa',
        'name': 'Тестировщик кода (QA)',
        'description': 'Написание Unit-тестов, поиск логических ошибок, багов и проверка граничных условий.',
        'prompt': 'Ты — QA инженер. Помогай писать Unit-тесты, искать логические ошибки и граничные случаи в предоставленном коде.'
      },
      {
        'id': 'chef',
        'name': 'Шеф-повар кулинарии',
        'description': 'Подбор рецептов по ингредиентам, кулинарные советы и составление здорового меню.',
        'prompt': 'Ты — профессиональный кулинарный шеф-повар. Помогай пользователю придумывать рецепты из имеющихся продуктов, давай советы по технике приготовления, замене ингредиентов и красивой подаче блюд.'
      },
      {
        'id': 'english',
        'name': 'Репетитор английского',
        'description': 'Практика общения, перевод, грамматика и мягкое исправление ошибок.',
        'prompt': 'Ты — дружелюбный и поддерживающий репетитор английского языка. Помогай пользователю изучать язык: отвечай на английском, переводи предложения, понятно объясняй правила грамматики и исправляй ошибки в сообщениях пользователя.'
      },
      {
        'id': 'copywriter',
        'name': 'Креативный копирайтер',
        'description': 'Создание текстов для постов, сценариев, статей, писем и праздничных поздравлений.',
        'prompt': 'Ты — талантливый копирайтер и креативный писатель. Твоя задача — создавать вовлекающие и качественные тексты, посты для соцсетей, сценарии, статьи и стихи в различных тонах речи (официальный, дружелюбный, юмористический) по запросу пользователя.'
      },
      {
        'id': 'fitness',
        'name': 'Фитнес-тренер и нутрициолог',
        'description': 'Составление безопасных тренировочных программ для дома/зала и расчет здорового рациона.',
        'prompt': 'Ты — опытный персональный фитнес-тренер и нутрициолог. Составляй безопасные и эффективные планы тренировок для дома или зала, давай рекомендации по расчету КБЖУ, питьевому режиму и здоровому образу жизни.'
      }
    ];

    bool listChanged = false;
    for (final def in defaultList) {
      final existsIndex = loadedProjects.indexWhere((p) => p['id'] == def['id']);
      if (existsIndex == -1) {
        loadedProjects.add(def);
        listChanged = true;
      } else {
        final current = loadedProjects[existsIndex];
        if (current['id'] == 'flutter' && current['description'] == 'Создание и отладка мобильных приложений на Flutter/Dart.') {
          loadedProjects[existsIndex]['description'] = def['description'];
          listChanged = true;
        } else if (current['id'] == 'python' && current['description'] == 'Разработка скриптов автоматизации, бэкенда на FastAPI, Django и парсеров.') {
          loadedProjects[existsIndex]['description'] = def['description'];
          listChanged = true;
        } else if (current['id'] == 'qa' && (current['description'] == 'Анализ багов, написание unit-тестов и проверка алгоритмов.' || current['name'] == 'Тестировщик кода')) {
          loadedProjects[existsIndex]['name'] = def['name'];
          loadedProjects[existsIndex]['description'] = def['description'];
          listChanged = true;
        }
      }
    }

    if (listChanged) {
      await prefs.setString('projects_list', jsonEncode(loadedProjects));
    }

    final activeId = prefs.getString('active_project_id') ?? 'default';
    final chats = await ChatHistory.getChats();

    setState(() {
      _projects = loadedProjects;
      _activeProjectId = activeId;
      _allChats = chats;
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

  Future<void> _selectProjectAndChat(String projId, int chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_project_id', projId);
    final activeProj = _projects.firstWhere((p) => p['id'] == projId, orElse: () => _projects.first);
    await prefs.setString('active_project_prompt', activeProj['prompt'] ?? '');
    setState(() {
      _activeProjectId = projId;
    });
    if (mounted) {
      Navigator.pop(context, {
        'projectId': projId,
        'chatId': chatId,
      });
    }
  }

  void _showDeleteConfirmation(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Удаление проекта', style: TextStyle(color: VegaTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Вы действительно хотите удалить проект "$name"? Все чаты, созданные в этом проекте, будут безвозвратно удалены вместе с ним.', style: const TextStyle(color: VegaTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteProject(id);
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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

    final projectChats = _allChats.where((c) => c['projectId'] == id).toList();
    for (final chat in projectChats) {
      final cId = chat['id'];
      if (cId is int) {
        await ChatHistory.deleteChat(cId);
      }
    }

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
              itemCount: customProjects.length,
              itemBuilder: (context, index) {
                final proj = customProjects[index];
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _selectProject(proj['id']!),
                            style: TextButton.styleFrom(
                              foregroundColor: VegaTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            child: const Text('Новый чат', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: VegaTheme.textSecondary),
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showCreateProjectDialog(projectToEdit: proj);
                              } else if (value == 'delete') {
                                _showDeleteConfirmation(proj['id']!, proj['name'] ?? '');
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit_outlined, color: VegaTheme.textSecondary, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Изменить', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Удалить', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(color: VegaTheme.border),
                              const SizedBox(height: 8),
                              const Text(
                                'Чаты проекта:',
                                style: TextStyle(color: VegaTheme.accent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Builder(builder: (ctx) {
                                final projectChats = _allChats.where((c) => c['projectId'] == proj['id']).toList();
                                if (projectChats.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'В этом проекте пока нет чатов',
                                      style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                                    ),
                                  );
                                }
                                return ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: projectChats.length,
                                  itemBuilder: (ctx, i) {
                                    final chat = projectChats[i];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: VegaTheme.dark.withOpacity(0.4),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                        leading: const Icon(Icons.chat_bubble_outline_rounded, color: VegaTheme.accent, size: 20),
                                        title: Text(
                                          chat['title'] ?? 'Без названия',
                                          style: const TextStyle(
                                            color: VegaTheme.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: const Icon(Icons.chevron_right_rounded, color: VegaTheme.textSecondary, size: 18),
                                        onTap: () {
                                          _selectProjectAndChat(proj['id']!, chat['id'] as int);
                                        },
                                      ),
                                    );
                                  },
                                );
                              }),
                              const SizedBox(height: 8),
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
