import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../data/chat_history.dart';

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  String toHex() => '#${value.toRadixString(16).substring(2, 8).toUpperCase()}';
}

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

    final List<Map<String, dynamic>> defaultList = [
      {
        'id': 'default',
        'name': 'Общий помощник',
        'description': 'Универсальный ИИ-помощник без специфичных системных инструкций.',
        'prompt': 'Ты — полезный, дружелюбный и умный ИИ-ассистент.',
        'iconName': 'school',
        'iconColor': '#555555',
        'suggestions': ['Написать код', 'Объяснить тему', 'Написать текст', 'Придумать идею']
      },
      {
        'id': 'flutter',
        'name': 'Flutter-разработчик',
        'description': 'Проектирование архитектуры и написание кода мобильных приложений на Dart.',
        'prompt': 'Ты — эксперт по разработке мобильных приложений на Flutter и Dart. Пиши чистый, оптимизированный код, следуй правилам чистой архитектуры.',
        'iconName': 'code',
        'iconColor': '#36A2EB',
        'suggestions': ['Создать виджет', 'Найти баг', 'State Management', 'Оптимизация']
      },
      {
        'id': 'python',
        'name': 'Python-разработчик',
        'description': 'Автоматизация задач, парсинг сайтов, разработка бэкенда на FastAPI/Django и работа с данными.',
        'prompt': 'Ты — опытный Senior Python разработчик. Пиши чистый, питоничный код (PEP 8), помогай писать автоматизацию и веб-приложения на FastAPI/Django.',
        'iconName': 'terminal',
        'iconColor': '#4BC080',
        'suggestions': ['Написать скрипт', 'Создать парсер', 'Написать API', 'Анализ Pandas']
      },
      {
        'id': 'qa',
        'name': 'Тестировщик кода (QA)',
        'description': 'Написание Unit-тестов, поиск логических ошибок, багов и проверка граничных условий.',
        'prompt': 'Ты — QA инженер. Помогай писать Unit-тесты, искать логические ошибки и граничные случаи в предоставленном коде.',
        'iconName': 'bug',
        'iconColor': '#FFCD56',
        'suggestions': ['Написать тесты', 'Найти баги', 'Тест-кейс', 'Автотест']
      },
      {
        'id': 'chef',
        'name': 'Шеф-повар кулинарии',
        'description': 'Подбор рецептов по ингредиентам, кулинарные советы и составление здорового меню.',
        'prompt': 'Ты — профессиональный кулинарный шеф-повар. Помогай пользователю придумывать аппетитные рецепты из имеющихся продуктов, давай советы по технике приготовления, замене ингредиентов и красивой подаче блюд.',
        'iconName': 'cake',
        'iconColor': '#FF9F40',
        'suggestions': ['Рецепт из продуктов', 'Пошаговый рецепт', 'Полезный салат', 'Секрет шефа']
      },
      {
        'id': 'english',
        'name': 'Репетитор английского',
        'description': 'Практика общения, перевод, грамматика и мягкое исправление ошибок.',
        'prompt': 'Ты — дружелюбный и поддерживающий репетитор английского языка. Помогай пользователю изучать язык: отвечай на английском, переводи предложения, понятно объясняй правила грамматики и исправляй ошибки в сообщениях пользователя.',
        'iconName': 'language',
        'iconColor': '#FF6384',
        'suggestions': ['Практика диалога', 'Проверить ошибки', 'Объяснить времена', 'Сленг и идиомы']
      },
      {
        'id': 'copywriter',
        'name': 'Креативный копирайтер',
        'description': 'Создание текстов для постов, сценариев, статей, писем и праздничных поздравлений.',
        'prompt': 'Ты — талантливый копирайтер и креативный писатель. Твоя задача — создавать вовлекающие и качественные тексты, посты для соцсетей, сценарии, статьи и стихи в различных тонах речи (официальный, дружелюбный, юмористический) по запросу пользователя.',
        'iconName': 'edit',
        'iconColor': '#9966FF',
        'suggestions': ['Пост для блога', 'Email-рассылка', 'Сценарий Reels', 'Яркий слоган']
      },
      {
        'id': 'fitness',
        'name': 'Фитнес-тренер и нутрициолог',
        'description': 'Составление безопасных тренировочных программ для дома/зала и расчет здорового рациона.',
        'prompt': 'Ты — опытный персональный фитнес-тренер и нутрициолог. Составляй безопасные и эффективные планы тренировок для дома или зала, давай рекомендации по расчету КБЖУ, питьевому режиму и здоровому образу жизни.',
        'iconName': 'fitness',
        'iconColor': '#FF4D4D',
        'suggestions': ['План тренировки', 'Норма КБЖУ', 'Подготовка к бегу', 'Норма воды']
      }
    ];

    if (loadedProjects.isEmpty) {
      loadedProjects = List<Map<String, dynamic>>.from(defaultList);
      await prefs.setString('projects_list', jsonEncode(loadedProjects));
    }

    bool listChanged = false;
    for (final def in defaultList) {
      final existsIndex = loadedProjects.indexWhere((p) => p['id'] == def['id']);
      if (existsIndex == -1) {
        loadedProjects.add(def);
        listChanged = true;
      } else {
        final current = loadedProjects[existsIndex];
        bool needsUpdate = false;
        if (current['iconName'] == null) {
          loadedProjects[existsIndex]['iconName'] = def['iconName'];
          needsUpdate = true;
        }
        if (current['iconColor'] == null) {
          loadedProjects[existsIndex]['iconColor'] = def['iconColor'];
          needsUpdate = true;
        }
        if (current['suggestions'] == null) {
          loadedProjects[existsIndex]['suggestions'] = def['suggestions'];
          needsUpdate = true;
        }
        
        if (current['id'] == 'flutter' && current['description'] == 'Создание и отладка мобильных приложений на Flutter/Dart.') {
          loadedProjects[existsIndex]['description'] = def['description'];
          needsUpdate = true;
        } else if (current['id'] == 'python' && current['description'] == 'Разработка скриптов автоматизации, бэкенда на FastAPI, Django и парсеров.') {
          loadedProjects[existsIndex]['description'] = def['description'];
          needsUpdate = true;
        } else if (current['id'] == 'qa' && (current['description'] == 'Анализ багов, написание unit-тестов и проверка алгоритмов.' || current['name'] == 'Тестировщик кода')) {
          loadedProjects[existsIndex]['name'] = def['name'];
          loadedProjects[existsIndex]['description'] = def['description'];
          needsUpdate = true;
        }

        if (needsUpdate) {
          listChanged = true;
        }
      }
    }

    for (int i = 0; i < loadedProjects.length; i++) {
      final p = loadedProjects[i];
      bool needsUpdate = false;
      if (p['iconName'] == null) {
        loadedProjects[i]['iconName'] = 'folder';
        needsUpdate = true;
      }
      if (p['iconColor'] == null) {
        loadedProjects[i]['iconColor'] = '#555555';
        needsUpdate = true;
      }
      if (p['suggestions'] == null) {
        loadedProjects[i]['suggestions'] = <String>[];
        needsUpdate = true;
      }
      if (needsUpdate) {
        listChanged = true;
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
    final activeProj = _projects.firstWhere((p) => p['id'] == id, orElse: () => _projects.first);
    await prefs.setString('active_project_prompt', activeProj['prompt'] ?? '');
    setState(() {
      _activeProjectId = id;
    });
    if (mounted) {
      Navigator.pop(context, true);
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

  Future<void> _createProject(String name, String description, String prompt, String iconName, String iconColor, List<String> suggestions) async {
    final prefs = await SharedPreferences.getInstance();
    final newProjId = DateTime.now().millisecondsSinceEpoch.toString();
    final newProj = {
      'id': newProjId,
      'name': name,
      'description': description,
      'prompt': prompt,
      'iconName': iconName,
      'iconColor': iconColor,
      'suggestions': suggestions,
    };
    setState(() {
      _projects.add(newProj);
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    await _selectProject(newProjId);
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

  Future<void> _editProject(String id, String name, String description, String prompt, String iconName, String iconColor, List<String> suggestions) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final index = _projects.indexWhere((p) => p['id'] == id);
      if (index != -1) {
        _projects[index] = {
          'id': id,
          'name': name,
          'description': description,
          'prompt': prompt,
          'iconName': iconName,
          'iconColor': iconColor,
          'suggestions': suggestions,
        };
      }
    });
    await prefs.setString('projects_list', jsonEncode(_projects));
    if (_activeProjectId == id) {
      await prefs.setString('active_project_prompt', prompt);
    }
    _loadProjects();
  }

  Future<Map<String, String>?> _showIconPickerDialog(String initialIcon, String initialColor) async {
    String selectedIcon = initialIcon;
    String selectedColor = initialColor;

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

    return showDialog<Map<String, String>>(
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
                      backgroundColor: HexColor.fromHex(selectedColor),
                      child: Icon(_getIconData(selectedIcon), color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 44,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: colors.length,
                        itemBuilder: (context, idx) {
                          final colorHex = colors[idx];
                          final isSelected = colorHex == selectedColor;
                          return GestureDetector(
                            onTap: () {
                              dialogSetState(() => selectedColor = colorHex);
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
                          final isSelected = iconName == selectedIcon;
                          return GestureDetector(
                            onTap: () {
                              dialogSetState(() => selectedIcon = iconName);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? HexColor.fromHex(selectedColor).withOpacity(0.2) 
                                    : VegaTheme.dark.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected 
                                      ? HexColor.fromHex(selectedColor) 
                                      : VegaTheme.border.withOpacity(0.3),
                                  width: isSelected ? 1.5 : 0.5,
                                ),
                              ),
                              child: Icon(
                                _getIconData(iconName),
                                color: isSelected 
                                    ? HexColor.fromHex(selectedColor) 
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
                    Navigator.pop(ctx, {'icon': selectedIcon, 'color': selectedColor});
                  },
                  child: const Text('OK', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateProjectDialog({Map<String, dynamic>? projectToEdit}) {
    final isEdit = projectToEdit != null;
    final nameCtrl = TextEditingController(text: isEdit ? projectToEdit['name'] : '');
    final descCtrl = TextEditingController(text: isEdit ? projectToEdit['description'] : '');
    final promptCtrl = TextEditingController(text: isEdit ? projectToEdit['prompt'] : '');
    
    String selectedIcon = isEdit ? (projectToEdit['iconName'] ?? 'folder') : 'folder';
    String selectedColor = isEdit ? (projectToEdit['iconColor'] ?? '#555555') : '#555555';
    
    final initialSuggestions = isEdit && projectToEdit['suggestions'] != null
        ? List<String>.from(projectToEdit['suggestions']).join(', ')
        : '';
    final suggestionsCtrl = TextEditingController(text: initialSuggestions);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
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
                  // Icon preview & selector button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final result = await _showIconPickerDialog(selectedIcon, selectedColor);
                          if (result != null) {
                            dialogSetState(() {
                              selectedIcon = result['icon']!;
                              selectedColor = result['color']!;
                            });
                          }
                        },
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: HexColor.fromHex(selectedColor),
                              child: Icon(_getIconData(selectedIcon), color: Colors.white, size: 36),
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
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
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: suggestionsCtrl,
                    style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Подсказки (через запятую)',
                      hintText: 'Например: Написать код, Найти ошибку',
                      hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
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
                  
                  final suggestionsList = suggestionsCtrl.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();

                  if (name.isNotEmpty) {
                    if (isEdit) {
                      _editProject(projectToEdit['id']!, name, desc, prompt, selectedIcon, selectedColor, suggestionsList);
                    } else {
                      _createProject(name, desc, prompt, selectedIcon, selectedColor, suggestionsList);
                    }
                    Navigator.pop(ctx);
                  }
                },
                child: Text(isEdit ? 'Сохранить' : 'Создать', style: const TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customProjects = _projects.where((p) => p['id'] != 'default').toList();

    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Проекты',
          style: TextStyle(
            color: VegaTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _showCreateProjectDialog(),
            icon: const Icon(Icons.add_rounded, color: VegaTheme.accent, size: 28),
          ),
        ],
      ),
      body: customProjects.isEmpty
          ? const Center(
              child: Text(
                'Нет кастомных проектов.\nСоздайте новый!',
                textAlign: TextAlign.center,
                style: TextStyle(color: VegaTheme.textSecondary, fontSize: 14),
              ),
            )
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
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: HexColor.fromHex(proj['iconColor'] ?? '#555555'),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getIconData(proj['iconName'] ?? 'folder'),
                          color: Colors.white,
                          size: 18,
                        ),
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
                              backgroundColor: isCurrent ? Colors.white.withOpacity(0.06) : VegaTheme.accent.withOpacity(0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(64, 28),
                            ),
                            child: Text(
                              isCurrent ? 'Выбран' : 'Выбрать',
                              style: TextStyle(
                                color: isCurrent ? VegaTheme.textSecondary : VegaTheme.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: VegaTheme.textSecondary),
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showCreateProjectDialog(projectToEdit: proj);
                              } else if (value == 'delete') {
                                _showDeleteConfirmation(proj['id']!, proj['name'] ?? '');
                              }
                            },
                            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    const Icon(Icons.edit_outlined, color: VegaTheme.textSecondary, size: 18),
                                    const SizedBox(width: 8),
                                    Text('Редактировать', style: TextStyle(color: VegaTheme.textPrimary.withOpacity(0.85), fontSize: 13)),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                    const SizedBox(width: 8),
                                    const Text('Удалить', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(color: VegaTheme.border, height: 1),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'История чатов проекта',
                                    style: TextStyle(
                                      color: VegaTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _selectProjectAndChat(proj['id']!, -1);
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      minimumSize: const Size(64, 24),
                                      backgroundColor: VegaTheme.accent.withOpacity(0.1),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    child: const Text(
                                      'Новый чат',
                                      style: TextStyle(color: VegaTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Builder(builder: (context) {
                                final projectChats = _allChats.where((c) => c['projectId'] == proj['id']).toList();
                                if (projectChats.isEmpty) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: const Center(
                                      child: Text(
                                        'В этом проекте пока нет чатов',
                                        style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
                                      ),
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
