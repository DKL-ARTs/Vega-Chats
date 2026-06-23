import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatHistory {
  static const String _key = 'chat_history';

  static Future<List<Map<String, dynamic>>> getChats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null || data.isEmpty) return [];
    try {
      final decoded = jsonDecode(data);
      if (decoded is! List) return [];
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveChats(List<Map<String, dynamic>> chats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(chats));
  }

  static Future<int> createChat(String title) async {
    final chats = await getChats();
    final id = DateTime.now().millisecondsSinceEpoch;
    final newChat = <String, dynamic>{
      'id': id,
      'title': title,
      'messages': <Map<String, dynamic>>[],
      'createdAt': DateTime.now().toIso8601String(),
    };
    chats.insert(0, newChat);
    await saveChats(chats);
    return id;
  }

  static Future<void> addMessage(
    int chatId,
    String role,
    String content, {
    String filePath = '',
    String fileName = '',
    bool isImage = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return;
    List<dynamic> chats;
    try {
      chats = jsonDecode(data) as List<dynamic>;
    } catch (e) {
      return;
    }
    for (int i = 0; i < chats.length; i++) {
      if (chats[i] is Map && chats[i]['id'] == chatId) {
        final chat = chats[i] as Map<String, dynamic>;
        final messages = (chat['messages'] as List?) ?? [];
        messages.add({
          'role': role,
          'content': content,
          'filePath': filePath,
          'fileName': fileName,
          'isImage': isImage,
          'createdAt': DateTime.now().toIso8601String(),
        });
        chat['messages'] = messages;
        await prefs.setString(_key, jsonEncode(chats));
        return;
      }
    }
  }

  static Future<List<Map<String, dynamic>>> getMessages(int chatId) async {
    final chats = await getChats();
    for (final chat in chats) {
      if (chat['id'] == chatId) {
        final messages = (chat['messages'] as List?) ?? [];
        return messages.cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  static Future<void> deleteChat(int chatId) async {
    final chats = await getChats();
    chats.removeWhere((c) => c['id'] == chatId);
    await saveChats(chats);
  }
}
