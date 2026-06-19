import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  final Map<String, String> _headers;

  ApiClient({this.baseUrl = 'http://127.0.0.1:8765', String? apiKey})
      : _headers = {
          'Content-Type': 'application/json',
          if (apiKey != null && apiKey.isNotEmpty)
            'Authorization': 'Bearer $apiKey',
        };

  Future<http.StreamedResponse> streamChat({
    required List<Map<String, String>> messages,
    String model = 'openrouter/auto',
  }) async {
    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/api/chat/stream'),
    );
    request.headers.addAll(_headers);
    request.body = jsonEncode({
      'messages': messages,
      'model': model,
    });
    return request.send();
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/read'),
      headers: _headers,
      body: jsonEncode({'path': path}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/write'),
      headers: _headers,
      body: jsonEncode({'path': path, 'content': content}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/files/list'),
      headers: _headers,
      body: jsonEncode({'path': path}),
    );
    return jsonDecode(resp.body);
  }
}
