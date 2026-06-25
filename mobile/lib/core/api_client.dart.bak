import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  String _cleanKey() {
    return apiKey.replaceAll(RegExp(r'\s+'), '');
  }

  Future<http.StreamedResponse> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'owl-alpha',
    List<Map<String, String>>? files,
  }) async {
    final body = <String, dynamic>{'messages': messages, 'model': model};
    if (files != null && files.isNotEmpty) body['files'] = files;
    final uri = Uri.parse('$baseUrl/api/chat/stream');
    final cleanKey = _cleanKey();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (cleanKey.isNotEmpty) 'Authorization': 'Bearer $cleanKey',
    };
    final req = http.Request('POST', uri);
    req.headers.addAll(headers);
    req.body = jsonEncode(body);
    return req.send();
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/read'), headers: _hdrs(), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/write'), headers: _hdrs(), body: jsonEncode({'path': path, 'content': content}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/list'), headers: _hdrs(), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }

  Map<String, String> _hdrs() {
    final k = _cleanKey();
    return {
      'Content-Type': 'application/json',
      if (k.isNotEmpty) 'Authorization': 'Bearer $k',
    };
  }
}
