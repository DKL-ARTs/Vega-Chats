import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = 'http://127.0.0.1:8765', this.apiKey = ''});

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) headers['Authorization'] = 'Bearer $apiKey';
    return headers;
  }

  Future<http.StreamedResponse> streamChat({
    required List<Map<String, String>> messages,
    String model = 'owl-alpha',
    List<Map<String, String>>? files,
  }) async {
    final body = <String, dynamic>{
      'messages': messages,
      'model': model,
    };
    if (files != null && files.isNotEmpty) {
      body['files'] = files;
    }
    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat/stream'));
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);
    return request.send();
  }
}
