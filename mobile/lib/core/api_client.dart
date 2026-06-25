import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  Future<http.StreamedResponse> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'owl-alpha',
    List<Map<String, String>>? files,
  }) async {
    final body = <String, dynamic>{'messages': messages, 'model': model};
    if (files != null && files.isNotEmpty) body['files'] = files;
    
    final cleanedKey = apiKey.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '');
    
    final uri = Uri.parse('$baseUrl/api/chat/stream');
    final req = http.Request('POST', uri);
    req.headers.set('Content-Type', 'application/json');
    if (cleanedKey.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer $cleanedKey');
    }
    req.body = jsonEncode(body);
    return req.send();
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
