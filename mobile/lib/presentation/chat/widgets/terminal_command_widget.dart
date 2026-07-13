import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/theme.dart';

class TerminalCommandWidget extends StatefulWidget {
  final String command;
  final Function(String output, bool success) onFinished;

  const TerminalCommandWidget({
    super.key,
    required this.command,
    required this.onFinished,
  });

  @override
  State<TerminalCommandWidget> createState() => _TerminalCommandWidgetState();
}

class _TerminalCommandWidgetState extends State<TerminalCommandWidget> {
  String _status = 'idle'; // 'idle' | 'running' | 'success' | 'error'
  final List<String> _outputLines = [];
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _channel;

  @override
  void dispose() {
    _channel?.sink.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String> _getWsUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String baseUrl = prefs.getString('base_url') ?? 'http://127.0.0.1:8000';
    String wsUrl;
    if (baseUrl.startsWith('https://')) {
      wsUrl = 'wss://' + baseUrl.substring(8);
    } else if (baseUrl.startsWith('http://')) {
      wsUrl = 'ws://' + baseUrl.substring(7);
    } else {
      wsUrl = 'wss://' + baseUrl;
    }
    if (wsUrl.endsWith('/')) wsUrl = wsUrl.substring(0, wsUrl.length - 1);
    return wsUrl + '/ws/terminal';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runCommand() async {
    setState(() {
      _status = 'running';
      _outputLines.clear();
      _outputLines.add('Запуск: ${widget.command}...\n');
    });

    try {
      final wsUrl = await _getWsUrl();
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _channel!.stream.listen(
        (data) {
          setState(() {
            _outputLines.add(data.toString());
            _scrollToBottom();
          });
        },
        onError: (e) {
          setState(() {
            _status = 'error';
            _outputLines.add('\nОшибка соединения: $e');
            _scrollToBottom();
          });
          widget.onFinished(_outputLines.join('\n'), false);
        },
        onDone: () {
          // If websocket closes, command execution has finished
          final fullOutput = _outputLines.join('\n');
          final isError = fullOutput.toLowerCase().contains('failed') || 
                          fullOutput.toLowerCase().contains('error') ||
                          fullOutput.toLowerCase().contains('exception');
          setState(() {
            _status = isError ? 'error' : 'success';
          });
          widget.onFinished(fullOutput, !isError);
        },
      );

      // Send command to shell
      _channel!.sink.add(widget.command);
    } catch (e) {
      setState(() {
        _status = 'error';
        _outputLines.add('\nНе удалось подключиться: $e');
      });
      widget.onFinished(_outputLines.join('\n'), false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (_status == 'running') {
      statusColor = VegaTheme.accent;
      statusIcon = Icons.hourglass_top_rounded;
      statusText = 'Выполняется...';
    } else if (_status == 'success') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_rounded;
      statusText = 'Выполнено успешно';
    } else if (_status == 'error') {
      statusColor = Colors.redAccent;
      statusIcon = Icons.error_rounded;
      statusText = 'Ошибка выполнения';
    } else {
      statusColor = VegaTheme.textSecondary;
      statusIcon = Icons.play_arrow_rounded;
      statusText = 'Ожидает запуска';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: VegaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _status == 'idle' ? VegaTheme.border : statusColor.withOpacity(0.5),
          width: _status == 'idle' ? 0.5 : 1.5,
        ),
        boxShadow: _status == 'running'
            ? [
                BoxShadow(
                  color: VegaTheme.accent.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: VegaTheme.dark.withOpacity(0.4),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, color: statusColor, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Запрос терминала',
                      style: TextStyle(
                        color: VegaTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Command preview/console
            Container(
              maxHeight: _status == 'idle' ? 80 : 200,
              color: const Color(0xFF0F172A), // Slate-900 terminal background
              padding: const EdgeInsets.all(12),
              child: _status == 'idle'
                  ? SingleChildScrollView(
                      child: Text(
                        '\$ ${widget.command}',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8), // Light blue command color
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _outputLines.length,
                      itemBuilder: (context, idx) {
                        return Text(
                          _outputLines[idx],
                          style: const TextStyle(
                            color: Color(0xFFF1F5F9), // Slate-100 terminal text
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
            ),

            // Actions footer
            if (_status == 'idle')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() => _status = 'error');
                        widget.onFinished('Отклонено пользователем.', false);
                      },
                      child: const Text(
                        'Отклонить',
                        style: TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _runCommand,
                      icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                      label: const Text('Запустить', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VegaTheme.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
