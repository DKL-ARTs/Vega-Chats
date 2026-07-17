import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';

// ──────────────────────────────────────────────
// Data models for agent events
// ──────────────────────────────────────────────

enum AgentStepType { thinking, toolCall, toolResult, message, done, error }

class AgentStep {
  final AgentStepType type;
  final String content;
  final String? toolName;
  final Map<String, dynamic>? args;
  final DateTime time;

  AgentStep({
    required this.type,
    required this.content,
    this.toolName,
    this.args,
  }) : time = DateTime.now();
}

// ──────────────────────────────────────────────
// Agent Screen
// ──────────────────────────────────────────────

class AgentScreen extends StatefulWidget {
  final ApiClient client;
  final String initialCwd;

  const AgentScreen({
    super.key,
    required this.client,
    required this.initialCwd,
  });

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen>
    with TickerProviderStateMixin {
  final _taskCtrl = TextEditingController();
  final _cwdCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _isRunning = false;
  bool _isDone = false;
  final List<AgentStep> _steps = [];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _cwdCtrl.text = widget.initialCwd;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    _cwdCtrl.dispose();
    _scrollCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addStep(AgentStep step) {
    if (!mounted) return;
    setState(() => _steps.add(step));
    _scrollToBottom();
  }

  Future<String> _getGeminiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('gemini_api_key') ?? '';
  }

  Future<void> _startAgent() async {
    final task = _taskCtrl.text.trim();
    final cwd = _cwdCtrl.text.trim();

    if (task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите задачу для агента'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final geminiKey = await _getGeminiKey();
    if (geminiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет Gemini API ключа. Добавьте его в настройках.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isRunning = true;
      _isDone = false;
      _steps.clear();
    });

    await widget.client.runAgent(
      task: task,
      cwd: cwd.isNotEmpty ? cwd : widget.initialCwd,
      geminiApiKey: geminiKey,
      onEvent: (event) {
        final type = event['type'] as String? ?? '';
        switch (type) {
          case 'thinking':
            _addStep(AgentStep(
              type: AgentStepType.thinking,
              content: 'Итерация ${event['iteration'] ?? ''}...',
            ));
          case 'tool_call':
            _addStep(AgentStep(
              type: AgentStepType.toolCall,
              content: _describeToolCall(
                event['tool'] as String? ?? '',
                event['args'] as Map<String, dynamic>? ?? {},
              ),
              toolName: event['tool'] as String?,
              args: event['args'] as Map<String, dynamic>?,
            ));
          case 'tool_result':
            _addStep(AgentStep(
              type: AgentStepType.toolResult,
              content: event['result'] as String? ?? '',
              toolName: event['tool'] as String?,
            ));
          case 'message':
            _addStep(AgentStep(
              type: AgentStepType.message,
              content: event['content'] as String? ?? '',
            ));
          case 'done':
            _addStep(AgentStep(
              type: AgentStepType.done,
              content: event['warning'] as String? ??
                  'Задача выполнена за ${event['iterations'] ?? '?'} итераций',
            ));
            if (mounted) setState(() { _isRunning = false; _isDone = true; });
          case 'error':
            _addStep(AgentStep(
              type: AgentStepType.error,
              content: event['message'] as String? ?? 'Неизвестная ошибка',
            ));
            if (mounted) setState(() { _isRunning = false; _isDone = true; });
        }
      },
      onError: (err) {
        _addStep(AgentStep(
          type: AgentStepType.error,
          content: err,
        ));
        if (mounted) setState(() { _isRunning = false; _isDone = true; });
      },
    );
  }

  String _describeToolCall(String tool, Map<String, dynamic> args) {
    switch (tool) {
      case 'read_file':
        return 'Читаю файл: ${args['path'] ?? ''}';
      case 'write_file':
        final lines = (args['content'] as String? ?? '').split('\n').length;
        return 'Записываю файл: ${args['path'] ?? ''} ($lines строк)';
      case 'list_files':
        return 'Просматриваю директорию: ${args['path'] ?? ''}';
      case 'run_command':
        return 'Выполняю: ${args['command'] ?? ''}';
      case 'create_directory':
        return 'Создаю папку: ${args['path'] ?? ''}';
      case 'delete_file':
        return 'Удаляю: ${args['path'] ?? ''}';
      case 'search_in_files':
        return 'Ищу "${args['query'] ?? ''}" в ${args['path'] ?? ''}';
      default:
        return '$tool(${args.entries.map((e) => '${e.key}: ${e.value}').join(', ')})';
    }
  }

  // ──────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: VegaTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vega Agent',
                    style: TextStyle(
                        color: VegaTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                Text('Автономный режим',
                    style: TextStyle(
                        color: VegaTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          if (_isRunning)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF22C55E)
                        .withOpacity(_pulseAnim.value),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Task Input Panel ──
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF6366F1).withOpacity(0.12),
                  const Color(0xFF8B5CF6).withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CWD row
                Row(
                  children: [
                    const Icon(Icons.folder_rounded,
                        color: Color(0xFFF59E0B), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _cwdCtrl,
                        enabled: !_isRunning,
                        style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 12,
                            fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: '/root/workspace',
                          hintStyle:
                              TextStyle(color: Colors.white30, fontSize: 12),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 10),

                // Task input
                TextField(
                  controller: _taskCtrl,
                  enabled: !_isRunning,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'Например: "Создай Flutter-приложение с главным экраном и нижней навигацией"',
                    hintStyle: TextStyle(
                        color: VegaTheme.textSecondary.withOpacity(0.6),
                        fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 12),

                // Start button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _isRunning ? null : _startAgent,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: _isRunning
                            ? null
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFF8B5CF6),
                                ],
                              ),
                        color: _isRunning ? Colors.white10 : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: _isRunning
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedBuilder(
                                  animation: _pulseAnim,
                                  builder: (_, __) => Icon(
                                    Icons.stop_circle_rounded,
                                    color: Colors.white
                                        .withOpacity(_pulseAnim.value),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('Агент работает...',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  _isDone
                                      ? '▶ Запустить снова'
                                      : '▶ Запустить агента',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Steps Log ──
          Expanded(
            child: _steps.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _steps.length,
                    itemBuilder: (context, i) => _buildStep(_steps[i], i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Color(0xFF6366F1), size: 48),
          ),
          const SizedBox(height: 16),
          const Text('Агент готов к работе',
              style: TextStyle(
                  color: VegaTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Введите задачу и нажмите "Запустить".\nАгент сам создаст файлы и запустит команды.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: VegaTheme.textSecondary.withOpacity(0.7),
                fontSize: 13,
                height: 1.5),
          ),
          const SizedBox(height: 24),
          // Example tasks
          _buildExampleTask('🐍 Создай Python скрипт парсера CSV'),
          _buildExampleTask('⚛️ Напиши React-компонент с хуками'),
          _buildExampleTask('📱 Создай новый Flutter экран'),
        ],
      ),
    );
  }

  Widget _buildExampleTask(String text) {
    return GestureDetector(
      onTap: () {
        final clean = text.replaceAll(RegExp(r'^[^\w]+'), '');
        _taskCtrl.text = clean;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(text,
            style: TextStyle(
                color: VegaTheme.textSecondary, fontSize: 13)),
      ),
    );
  }

  Widget _buildStep(AgentStep step, int index) {
    switch (step.type) {
      case AgentStepType.thinking:
        return _buildThinkingStep(step);
      case AgentStepType.toolCall:
        return _buildToolCallStep(step);
      case AgentStepType.toolResult:
        return _buildToolResultStep(step);
      case AgentStepType.message:
        return _buildMessageStep(step);
      case AgentStepType.done:
        return _buildDoneStep(step);
      case AgentStepType.error:
        return _buildErrorStep(step);
    }
  }

  Widget _buildThinkingStep(AgentStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (_isRunning && step == _steps.last)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Icon(
                Icons.psychology_rounded,
                color: const Color(0xFF6366F1).withOpacity(_pulseAnim.value),
                size: 16,
              ),
            )
          else
            const Icon(Icons.psychology_rounded,
                color: Color(0xFF6366F1), size: 16),
          const SizedBox(width: 8),
          Text(step.content,
              style: TextStyle(
                  color: VegaTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildToolCallStep(AgentStep step) {
    final icon = _toolIcon(step.toolName ?? '');
    final color = _toolColor(step.toolName ?? '');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _toolLabel(step.toolName ?? ''),
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(step.content,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolResultStep(AgentStep step) {
    final preview = step.content.length > 300
        ? step.content.substring(0, 300) + '…'
        : step.content;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        childrenPadding: EdgeInsets.zero,
        leading: const Icon(Icons.chevron_right_rounded,
            color: Colors.white24, size: 16),
        title: Text(
          '← ${_toolLabel(step.toolName ?? '')} результат',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: const SizedBox.shrink(),
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              preview,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageStep(AgentStep step) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 13),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(step.content,
                style: const TextStyle(
                    color: VegaTheme.textPrimary,
                    fontSize: 13,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep(AgentStep step) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF22C55E).withOpacity(0.12),
            const Color(0xFF16A34A).withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF22C55E).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF22C55E), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(step.content,
                style: const TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorStep(AgentStep step) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_rounded,
              color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(step.content,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  IconData _toolIcon(String tool) {
    switch (tool) {
      case 'read_file':
        return Icons.visibility_rounded;
      case 'write_file':
        return Icons.edit_rounded;
      case 'list_files':
        return Icons.folder_open_rounded;
      case 'run_command':
        return Icons.terminal_rounded;
      case 'create_directory':
        return Icons.create_new_folder_rounded;
      case 'delete_file':
        return Icons.delete_rounded;
      case 'search_in_files':
        return Icons.search_rounded;
      default:
        return Icons.build_rounded;
    }
  }

  Color _toolColor(String tool) {
    switch (tool) {
      case 'read_file':
        return const Color(0xFF38BDF8);
      case 'write_file':
        return const Color(0xFF4ADE80);
      case 'list_files':
        return const Color(0xFFF59E0B);
      case 'run_command':
        return const Color(0xFFA78BFA);
      case 'create_directory':
        return const Color(0xFF34D399);
      case 'delete_file':
        return const Color(0xFFF87171);
      case 'search_in_files':
        return const Color(0xFFFBBF24);
      default:
        return VegaTheme.accent;
    }
  }

  String _toolLabel(String tool) {
    switch (tool) {
      case 'read_file':
        return 'ЧИТАЮ ФАЙЛ';
      case 'write_file':
        return 'ЗАПИСЫВАЮ ФАЙЛ';
      case 'list_files':
        return 'ПРОСМАТРИВАЮ ПАПКУ';
      case 'run_command':
        return 'ВЫПОЛНЯЮ КОМАНДУ';
      case 'create_directory':
        return 'СОЗДАЮ ПАПКУ';
      case 'delete_file':
        return 'УДАЛЯЮ';
      case 'search_in_files':
        return 'ПОИСК В ФАЙЛАХ';
      default:
        return tool.toUpperCase();
    }
  }
}
