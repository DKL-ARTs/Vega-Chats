import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/theme.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _controller = TextEditingController();
  final _output = <String>[];
  WebSocketChannel? _channel;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:8765/ws/terminal'));
      _channel!.stream.listen(
        (data) {
          setState(() => _output.add(data.toString()));
        },
        onError: (e) {
          setState(() {
            _output.add('Error: $e');
            _connected = false;
          });
        },
        onDone: () {
          setState(() => _connected = false);
        },
      );
      setState(() => _connected = true);
    } catch (e) {
      setState(() {
        _output.add('Connection failed: $e');
        _connected = false;
      });
    }
  }

  void _sendCommand() {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty || _channel == null) return;
    _channel!.sink.add(cmd);
    setState(() => _output.add('$ ' + cmd));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('Terminal', style: TextStyle(color: VegaTheme.textPrimary)),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _output.length,
              itemBuilder: (ctx, i) => Text(
                _output[i],
                style: TextStyle(
                  color: _output[i].startsWith('$ ') ? VegaTheme.accent : VegaTheme.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: VegaTheme.surface,
            child: Row(
              children: [
                Text('$ ', style: TextStyle(color: VegaTheme.accent, fontFamily: 'monospace')),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: VegaTheme.textPrimary, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter command...',
                      hintStyle: TextStyle(color: VegaTheme.textSecondary),
                    ),
                    onSubmitted: (_) => _sendCommand(),
                  ),
                ),
                IconButton(
                  onPressed: _sendCommand,
                  icon: Icon(Icons.send, color: VegaTheme.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _controller.dispose();
    super.dispose();
  }
}
