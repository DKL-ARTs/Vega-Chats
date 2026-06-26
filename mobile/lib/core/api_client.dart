import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  Future<String> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'owl-alpha',
    List<Map<String, String>>? files,
  }) async {
    final body = <String, dynamic>{'messages': messages, 'model': model};
    if (files != null && files.isNotEmpty) body['files'] = files;
    final cleaned = apiKey.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '');
    final authValue = 'Bearer $cleaned';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (cleaned.isNotEmpty) {
      headers['Authorization'] = authValue;
    }
    final resp = await http.post(
      Uri.parse('$baseUrl/api/chat/stream'),
      headers: headers,
      body: jsonEncode(body),
    );
    
    // Debug: log raw response
    print('=== RESPONSE STATUS: ${resp.statusCode} ===');
    print('=== RESPONSE BODY (first 500 chars): ===');
    print(resp.body.substring(0, resp.body.length > 500 ? 500 : resp.body.length));
    
    // Parse SSE response
    final responseBody = resp.body;
    final lines = responseBody.split('\n');
    final contentBuffer = StringBuffer();
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('data: ')) {
        final jsonStr = trimmed.substring(6).trim();
        if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
        try {
          final chunk = jsonDecode(jsonStr) as Map<String, dynamic>;
          final choices = chunk['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta != null && delta.containsKey('content')) {
              contentBuffer.write(delta['content'] as String? ?? '');
            }
          }
        } catch (e) {
          print('JSON parse error: $e for: $jsonStr');
        }
      }
    }
    
    print('=== PARSED CONTENT: ${contentBuffer.toString().substring(0, contentBuffer.length > 200 ? 200 : contentBuffer.length)} ===');
    return contentBuffer.toString();
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/read'), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/write'), body: jsonEncode({'path': path, 'content': content}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/list'), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }
}
