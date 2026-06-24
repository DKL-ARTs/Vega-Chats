import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
    return headers;
  }

  Future<http.StreamedResponse> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'owl-alpha',
    List<Map<String, String>>? files,
  }) async {
    final body = <String, dynamic>{'messages': messages, 'model': model};
    if (files != null && files.isNotEmpty) body['files'] = files;
    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat/stream'));
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);
    return request.send();
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/read'), headers: _headers, body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/write'), headers: _headers, body: jsonEncode({'path': path, 'content': content}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/list'), headers: _headers, body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }
}
