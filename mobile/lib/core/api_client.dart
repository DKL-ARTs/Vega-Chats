import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  Future<void> _log(String msg) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('debug_log') ?? '';
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final newLog = existing + '[$ts] $msg\n';
    await prefs.setString('debug_log', newLog.length > 3000 ? newLog.substring(newLog.length - 3000) : newLog);
  }

  String _cleanKey() {
    final result = StringBuffer();
    for (int i = 0; i < apiKey.length; i++) {
      final ch = apiKey[i];
      if (RegExp(r'[a-zA-Z0-9\-_.]').hasMatch(ch)) {
        result.write(ch);
      }
    }
    return result.toString();
  }

  Future<String> getDebugLog() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('debug_log') ?? '(empty)';
  }

  Future<http.StreamedResponse> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'owl-alpha',
    List<Map<String, String>>? files,
  }) async {
    await _log('--- streamChat ---');
    await _log('apiKey raw: $apiKey len=${apiKey.length}');
    
    final body = <String, dynamic>{'messages': messages, 'model': model};
    if (files != null && files.isNotEmpty) body['files'] = files;
    final uri = Uri.parse('$baseUrl/api/chat/stream');
    final cleanKey = _cleanKey();
    await _log('cleanKey: $cleanKey len=${cleanKey.length}');
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (cleanKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $cleanKey';
    }
    await _log('headers: $headers');
    
    final req = http.Request('POST', uri);
    req.headers.addAll(headers);
    req.body = jsonEncode(body);
    try {
      final resp = await req.send();
      await _log('status: ${resp.statusCode}');
      return resp;
    } catch (e) {
      await _log('ERROR: $e');
      rethrow;
    }
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
