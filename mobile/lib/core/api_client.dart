import 'dart:convert';
import 'dart:io';
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
    
    // Use dart:io HttpClient directly to avoid http package header validation issues
    final client = HttpClient();
    final request = await client.postUrl(uri);
    final trimmed = apiKey.trim();
    if (trimmed.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer $trimmed');
    }
    request.headers.set('Content-Type', 'application/json');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    client.close();
    
    // Convert to http.StreamedResponse for compatibility
    return http.StreamedResponse(
      response.transform(utf8.decoder).transform(jsonDecoder),
      response.statusCode,
      headers: response.headers.toString(),
    );
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/read'), headers: _simpleHeaders(), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/write'), headers: _simpleHeaders(), body: jsonEncode({'path': path, 'content': content}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api/files/list'), headers: _simpleHeaders(), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }

  Map<String, String> _simpleHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final t = apiKey.trim();
    if (t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }
}
