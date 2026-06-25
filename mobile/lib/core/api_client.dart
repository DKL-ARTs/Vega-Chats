import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  String _cleanKey() {
    // Remove ALL whitespace characters (space, tab, nbsp, etc.)
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
    final bodyStr = jsonEncode(body);
    
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: 30);
    
    final request = await client.postUrl(uri);
    final cleanKey = _cleanKey();
    if (cleanKey.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $cleanKey');
    }
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.body = bodyStr;
    
    final response = await request.close();
    client.close();
    
    return http.StreamedResponse(
      response,
      response.statusCode,
    );
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
