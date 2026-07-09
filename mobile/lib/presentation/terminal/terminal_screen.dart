import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/theme.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _output = <String>[];
  WebSocketChannel? _channel;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
      
      // Convert http(s) to ws(s)
      String wsUrl;
      if (baseUrl.startsWith('https://')) {
        wsUrl = 'wss://' + baseUrl.substring(8);
      } else if (baseUrl.startsWith('http://')) {
        wsUrl = 'ws://' + baseUrl.substring(7);
      } else {
        wsUrl = 'wss://' + baseUrl;
      }
      // Remove trailing slash
      if (wsUrl.endsWith('/')) wsUrl = wsUrl.substring(0, wsUrl.length - 1);
      wsUrl += '/ws/terminal';

      setState(() => _output.add('Connecting to $wsUrl...'));

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (data) {
          setState(() {
            _output.add(data.toString());
            _scrollToBottom();
          });
        },
        onError: (e) {
          setState(() {
            _output.add('Error: $e');
            _connected = false;
          });
        },
        onDone: () {
          setState(() {
            _output.add('Disconnected.');
            _connected = false;
          });
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendCommand() {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty || _channel == null) return;
    _channel!.sink.add(cmd);
    setState(() {
      _output.add(r'$ ' + cmd);
      _scrollToBottom();
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('Terminal', style: TextStyle(color: VegaTheme.textPrimary)),
        actions: [
          if (!_connected)
            IconButton(
              icon: Icon(Icons.refresh, color: VegaTheme.textSecondary),
              onPressed: _connect,
            ),
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
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _output.length,
              itemBuilder: (ctx, i) => SelectableText(
                _output[i],
                style: TextStyle(
                  color: _output[i].startsWith(r'$ ') ? VegaTheme.accent : VegaTheme.textPrimary,
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
                Text(r'$ ', style: TextStyle(color: VegaTheme.accent, fontFamily: 'monospace')),
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
    _scrollController.dispose();
    super.dispose();
  }
}
