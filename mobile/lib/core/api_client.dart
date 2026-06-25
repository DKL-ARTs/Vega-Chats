import 'dart:convert';
import 'dart:io';
import 'dart:async';
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
    final uri = Uri.parse('$baseUrl/api/chat/stream');
    final bodyBytes = utf8.encode(jsonEncode(body));
    
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: 30);
    
    final request = await client.postUrl(uri);
    final t = apiKey.trim();
    if (t.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
    }
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
    
    final response = await request.close();
    client.close();
    
    return http.StreamedResponse(
      response,
      response.statusCode,
      
      headers: {},
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
    final t = apiKey.trim();
    return {
      'Content-Type': 'application/json',
      if (t.isNotEmpty) 'Authorization': 'Bearer $t',
    };
  }
}
