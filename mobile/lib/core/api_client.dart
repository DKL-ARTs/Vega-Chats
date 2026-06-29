import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  String baseUrl;
  String apiKey;

  ApiClient({this.baseUrl = '', this.apiKey = ''});

  Future<void> streamChat({
    required List<Map<String, dynamic>> messages,
    String model = 'owl-alpha',
    List<Map<String, String>>? files,
    required void Function(String chunk) onChunk,
    required Function onError,
  }) async {
    final body = <String, dynamic>{'messages': messages, 'model': model};
    if (files != null && files.isNotEmpty) body['files'] = files;
    final cleaned = apiKey.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.]'), '');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (cleaned.isNotEmpty) {
      headers['Authorization'] = 'Bearer $cleaned';
    }

    try {
      final client = http.Client();
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat/stream'));
      request.headers.addAll(headers);
      request.body = jsonEncode(body);

      final streamedResponse = await client.send(request);
      
      if (streamedResponse.statusCode != 200) {
        onError('HTTP ${streamedResponse.statusCode}');
        client.close();
        return;
      }

      print('STREAM: status=${streamedResponse.statusCode}');
      int chunkCount = 0;
      int totalBytes = 0;
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        chunkCount++;
        totalBytes += chunk.length;
        print('STREAM chunk #$chunkCount: ${chunk.length} chars, total=$totalBytes');
        print('STREAM raw chunk: ${chunk.substring(0, chunk.length > 200 ? 200 : chunk.length)}');
        final cleanChunk = chunk.replaceAll('\r', '');
        final lines = cleanChunk.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed.startsWith('data: ')) {
            final data = trimmed.substring(6).trim();
            if (data == '[DONE]') return;
            if (data.startsWith('Error:')) {
              print('STREAM Error: $data');
              onError(data.substring(6));
              return;
            }
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final content = json['content'] as String?;
              if (content != null && content.isNotEmpty) {
                print('STREAM content: "$content"');
                onChunk(content);
              }
            } catch (e) {
              print('STREAM json parse error: $e');
              print('STREAM raw data: "$data"');
              // If JSON parse fails, treat as raw text chunk
              onChunk(data);
            }
          } else if (!trimmed.startsWith(':')) {
            // Non-SSE line, treat as raw text
            print('STREAM non-SSE: "$trimmed"');
            onChunk(trimmed);
          }
        }
      }
      print('STREAM ended: $chunkCount chunks, $totalBytes bytes total');
    } catch (e) {
      onError(e.toString());
    }
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
