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
    final cleaned = apiKey.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '');
    final url = Uri.parse(baseUrl + '/api/chat/stream');
    final bodyStr = jsonEncode(body);
    final bodyBytes = utf8.encode(bodyStr);
    final isHttps = url.scheme == 'https';
    final port = url.port != 0 ? url.port : (isHttps ? 443 : 80);
    final socket = isHttps
        ? await SecureSocket.connect(url.host, port)
        : await Socket.connect(url.host, port);
    final sb = StringBuffer();
    sb.writeln('POST ' + url.path + ' HTTP/1.1');
    sb.writeln('Host: ' + url.host + ':' + port.toString());
    sb.writeln('Content-Type: application/json');
    sb.writeln('Content-Length: ' + bodyBytes.length.toString());
    if (cleaned.isNotEmpty) {
      sb.writeln('Bearer ' + cleaned);
    }
    sb.writeln();
    socket.write(sb.toString());
    socket.add(bodyBytes);
    await socket.flush();
    print("[SOCKET] Request sent, waiting for response...");
    return http.StreamedResponse(socket, 200);
  }

  Future<Map<String, dynamic>> readFile(String path) async {
    final resp = await http.post(Uri.parse(baseUrl + '/api/files/read'), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> writeFile(String path, String content) async {
    final resp = await http.post(Uri.parse(baseUrl + '/api/files/write'), body: jsonEncode({'path': path, 'content': content}));
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await http.post(Uri.parse(baseUrl + '/api/files/list'), body: jsonEncode({'path': path}));
    return jsonDecode(resp.body);
  }
}
