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
      // CRITICAL: Buffer incomplete SSE events. SSE events are separated by \n\n,
      // but JSON content can contain \n which must NOT be treated as event boundary.
      final sseBuffer = StringBuffer();
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        chunkCount++;
        totalBytes += chunk.length;
        sseBuffer.write(chunk.replaceAll('\r', ''));
        // Process all complete SSE events in the buffer
        while (true) {
          final bufStr = sseBuffer.toString();
          final eventEnd = bufStr.indexOf('\n\n');
          if (eventEnd < 0) break; // incomplete event, wait for more data
          final eventStr = bufStr.substring(0, eventEnd);
          sseBuffer.clear();
          sseBuffer.write(bufStr.substring(eventEnd + 2));
          // Extract all data: lines from this event
          final dataLines = <String>[];
          for (final line in eventStr.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.startsWith('data: ')) {
              dataLines.add(trimmed.substring(6).trim());
            }
          }
          if (dataLines.isEmpty) continue;
          final data = dataLines.join('\n');
          if (data == '[DONE]') {
            print('STREAM: [DONE] received, total=$totalBytes');
            return;
          }
          if (data.startsWith('Error:')) {
            print('STREAM Error: $data');
            onError(data.substring(6));
            return;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final content = json['content'] as String?;
            if (content != null && content.isNotEmpty) {
              onChunk(content);
            }
          } catch (e) {
            // JSON parse failed - try to extract content manually
            final match = RegExp(r'"content"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(data);
            if (match != null) {
              final extracted = match.group(1) ?? '';
              if (extracted.isNotEmpty) onChunk(extracted);
            }
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
