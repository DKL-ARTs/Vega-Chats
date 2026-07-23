import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  Future<void> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'openrouter/auto',
    String provider = 'openrouter',
    String geminiApiKey = '',
    String systemPrompt = '',
    List<Map<String, String>>? files,
    required void Function(String chunk) onChunk,
    required Function onError,
  }) async {
    final wsScheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final cleanUrl = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    final wsUrl = '$wsScheme://$cleanUrl';
    
    WebSocketChannel? channel;
    try {
      print('STREAM WS: Connecting to $wsUrl/api/chat/ws');
      channel = WebSocketChannel.connect(Uri.parse('$wsUrl/api/chat/ws'));
      
      final requestPayload = <String, dynamic>{
        'messages': messages,
        'model': model,
        'provider': provider,
        'api_key': apiKey,
      };
      if (systemPrompt.isNotEmpty) {
        requestPayload['system_prompt'] = systemPrompt;
      }
      if (geminiApiKey.isNotEmpty) {
        requestPayload['gemini_api_key'] = geminiApiKey;
      }
      if (files != null && files.isNotEmpty) {
        requestPayload['files'] = files;
      }
      
      channel.sink.add(jsonEncode(requestPayload));
      
      await for (final message in channel.stream) {
        try {
          final data = jsonDecode(message) as Map<String, dynamic>;
          if (data.containsKey('error')) {
            onError(data['error']);
            return;
          }
          if (data.containsKey('done') && data['done'] == true) {
            print('STREAM WS: completed successfully');
            return;
          }
          final content = data['content'] as String?;
          if (content != null && content.isNotEmpty) {
            onChunk(content);
          }
        } catch (e) {
          print('STREAM WS parse error: $e');
        }
      }
    } catch (e) {
      onError(e.toString());
    } finally {
      channel?.sink.close();
    }
  }

  /// Run the autonomous agent. Streams events via callbacks.
  Future<void> runAgent({
    required String task,
    required String cwd,
    required String geminiApiKey,
    String model = 'gemini-3.6-flash',
    int maxIterations = 30,
    required void Function(Map<String, dynamic> event) onEvent,
    required void Function(String error) onError,
  }) async {
    final wsScheme = baseUrl.startsWith('https') ? 'wss' : 'ws';
    final cleanUrl = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    final wsUrl = '$wsScheme://$cleanUrl';

    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse('$wsUrl/api/agent/run'));

      // Send initial config
      channel.sink.add(jsonEncode({
        'task': task,
        'cwd': cwd,
        'gemini_api_key': geminiApiKey,
        'model': model,
        'max_iterations': maxIterations,
      }));

      await for (final raw in channel.stream) {
        try {
          final event = jsonDecode(raw as String) as Map<String, dynamic>;
          onEvent(event);
          if (event['type'] == 'done' || event['type'] == 'error') break;
        } catch (e) {
          print('Agent WS parse error: $e');
        }
      }
    } catch (e) {
      onError(e.toString());
    } finally {
      channel?.sink.close();
    }
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/read'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/write'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path, 'content': content}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/list'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> deleteFile(String path) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/delete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> renameFile(String oldPath, String newPath) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/rename'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'old_path': oldPath, 'new_path': newPath}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitStatus({String? cwd}) async {
    final uri = Uri.parse('$baseUrl/api/git/status').replace(
      queryParameters: cwd != null ? {'cwd': cwd} : null,
    );
    final resp = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitInit(String path) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/git/init'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitCommitPush(String message, {String? cwd}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/git/commit-push'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': message, if (cwd != null) 'cwd': cwd}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitStage(String filePath, {String? cwd}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/git/stage'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'file_path': filePath, if (cwd != null) 'cwd': cwd}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitUnstage(String filePath, {String? cwd}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/git/unstage'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'file_path': filePath, if (cwd != null) 'cwd': cwd}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitDiff({String? filePath, String? cwd}) async {
    final qParams = <String, String>{};
    if (filePath != null) qParams['file_path'] = filePath;
    if (cwd != null) qParams['cwd'] = cwd;
    final uri = Uri.parse('$baseUrl/api/git/diff').replace(
      queryParameters: qParams.isNotEmpty ? qParams : null,
    );
    final resp = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitBranches({String? cwd}) async {
    final uri = Uri.parse('$baseUrl/api/git/branches').replace(
      queryParameters: cwd != null ? {'cwd': cwd} : null,
    );
    final resp = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitCheckout(String branchName, {bool create = false, String? cwd}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/git/checkout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'branch_name': branchName,
        'create': create,
        if (cwd != null) 'cwd': cwd,
      }),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> gitPull({String? cwd}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/git/pull'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({if (cwd != null) 'cwd': cwd, 'message': ''}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> searchInFiles(String query, {String? cwd}) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, if (cwd != null) 'cwd': cwd}),
    );
    return jsonDecode(resp.body);
  }

  Future<String> chat({
    required List<Map<String, dynamic>> messages,
    String model = 'openrouter/auto',
    List<Map<String, String>>? files,
  }) async {
    final body = <String, dynamic>{'messages': messages, 'model': model};
    if (files != null && files.isNotEmpty) body['files'] = files;
    final cleaned = apiKey.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (cleaned.isNotEmpty) {
      headers['Authorization'] = 'Bearer $cleaned';
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/chat/stream'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      print('[CHAT] HTTP error: ${response.statusCode} ${response.body.substring(0, 200)}');
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    print('[CHAT] Got response, body length: ${response.body.length}');
    // Parse SSE response to extract final content
    final lines = response.body.split('\n');
    final buffer = StringBuffer();
    int chunkCount = 0;
    for (final line in lines) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data == '[DONE]' || data.isEmpty) continue;
        try {
          final json = jsonDecode(data);
          final content = json['content'];
          if (content != null) {
            buffer.write(content);
            chunkCount++;
          }
        } catch (_) {}
      }
    }
    print('[CHAT] Parsed $chunkCount chunks, total length: ${buffer.length}');
    final result = buffer.toString();
    print('[CHAT] First 200 chars: ${result.substring(0, result.length > 200 ? 200 : result.length)}');
    return result;
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final resp = await http.get(Uri.parse('$baseUrl/api/profile'));
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<void> updateUserProfile(Map<String, dynamic> profile) async {
    await http.post(
      Uri.parse('$baseUrl/api/profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(profile),
    );
  }

  Future<Map<String, dynamic>> deleteUserProfile() async {
    final resp = await http.delete(Uri.parse('$baseUrl/api/profile'));
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<Map<String, dynamic>> updateProfileManual(String text) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/profile/update_manual'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }
}
