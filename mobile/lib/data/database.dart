import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

class Chats extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 100)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get chatId => integer().references(Chats, #id)();
  TextColumn get role => text().withLength(min: 1, max: 20)();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Chats, Messages])
class AppDatabase extends _ {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<int> createChat(String title) async {
    return into(chats).insert(ChatsCompanion.insert(title: title));
  }

  Future<List<Chat>> getAllChats() async {
    return select(chats).get();
  }

  Future<Chat?> getChat(int id) async {
    return (select(chats)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<bool> updateChat(int id, String title) async {
    return update(chats).replace(ChatsCompanion(
      id: Value(id),
      title: Value(title),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<int> deleteChat(int id) async {
    await (delete(messages)..where((m) => m.chatId.equals(id))).go();
    return (delete(chats)..where((c) => c.id.equals(id))).go();
  }

  Future<int> addMessage(int chatId, String role, String content) async {
    return into(messages).insert(MessagesCompanion.insert(
      chatId: chatId,
      role: role,
      content: content,
    ));
  }

  Future<List<Message>> getMessages(int chatId) async {
    return (select(messages)..where((m) => m.chatId.equals(chatId))).get();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'vega_chat.db'));
    return NativeDatabase(file);
  });
}
