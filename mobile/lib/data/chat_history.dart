import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatHistory {
  static const String _key = 'chat_history';

  static Future<List<Map<String, dynamic>>> getChats() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(data));
  }

  static Future<void> saveChats(List<Map<String, dynamic>> chats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(chats));
  }

  static Future<int> createChat(String title) async {
    final chats = await getChats();
    final id = DateTime.now().millisecondsSinceEpoch;
    chats.insert(0, {
      'id': id,
      'title': title,
      'messages': [],
      'createdAt': DateTime.now().toIso8601String(),
    });
    await saveChats(chats);
    return id;
  }

  static Future<void> addMessage(int chatId, String role, String content, {String? filePath, String? fileName, bool isImage = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return;
    final chats = List<Map<String, dynamic>>.from(jsonDecode(data));
    final chatIndex = chats.indexWhere((c) => c['id'] == chatId);
    if (chatIndex != -1) {
      final messages = List<Map<String, dynamic>>.from(chats[chatIndex]['messages'] ?? []);
      messages.add({
        'role': role,
        'content': content,
        'filePath': filePath ?? '',
        'fileName': fileName ?? '',
        'isImage': isImage,
        'createdAt': DateTime.now().toIso8601String(),
      });
      chats[chatIndex]['messages'] = messages;
      await prefs.setString(_key, jsonEncode(chats));
    }
  }

  static Future<List<Map<String, dynamic>>> getMessages(int chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    final chats = List<Map<String, dynamic>>.from(jsonDecode(data));
    final chatIndex = chats.indexWhere((c) => c['id'] == chatId);
    if (chatIndex == -1) return [];
    return List<Map<String, dynamic>>.from(chats[chatIndex]['messages'] ?? []);
  }

  static Future<void> deleteChat(int chatId) async {
    final chats = await getChats();
    chats.removeWhere((c) => c['id'] == chatId);
    await saveChats(chats);
  }
}
