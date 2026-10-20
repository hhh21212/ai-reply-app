import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// 数据库查询封装，作为 [AppDatabase] 的扩展方法使用。
extension AppDatabaseDao on AppDatabase {
  // ---------- 会话 ----------

  Future<Conversation> createConversation({String title = '新对话'}) {
    return into(conversations)
        .insertReturning(ConversationsCompanion.insert(title: Value(title)));
  }

  Stream<List<Conversation>> watchConversations() {
    return (select(conversations)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  Future<Conversation?> getConversation(int id) {
    return (select(conversations)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> touchConversation(int id) {
    return (update(conversations)..where((t) => t.id.equals(id)))
        .write(ConversationsCompanion(updatedAt: Value(DateTime.now())));
  }

  Future<void> setConversationTitle(int id, String title) {
    return (update(conversations)..where((t) => t.id.equals(id)))
        .write(ConversationsCompanion(title: Value(title)));
  }

  Future<void> setConversationArchived(int id, bool archived) {
    return (update(conversations)..where((t) => t.id.equals(id)))
        .write(ConversationsCompanion(archived: Value(archived)));
  }

  Future<void> deleteConversation(int id) async {
    await (update(archiveEntries)
          ..where((t) => t.conversationId.equals(id)))
        .write(const ArchiveEntriesCompanion(conversationId: Value(null)));
    await (delete(messages)..where((t) => t.conversationId.equals(id))).go();
    await (delete(conversations)..where((t) => t.id.equals(id))).go();
  }

  // ---------- 消息 ----------

  Stream<List<Message>> watchMessages(int conversationId) {
    return (select(messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .watch();
  }

  Future<List<Message>> getMessages(int conversationId) {
    return (select(messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<Message> addMessage(int conversationId, String role, String content) {
    return into(messages).insertReturning(MessagesCompanion.insert(
      conversationId: conversationId,
      role: role,
      content: content,
    ));
  }

  // ---------- 档案 ----------

  Future<ArchiveEntry> addArchiveEntry({
    int? conversationId,
    required String title,
    required String summary,
    required List<String> keyPoints,
    required List<String> tags,
  }) {
    return into(archiveEntries).insertReturning(ArchiveEntriesCompanion.insert(
      conversationId: Value(conversationId),
      title: title,
      summary: summary,
      keyPointsJson: Value(jsonEncode(keyPoints)),
      tagsJson: Value(jsonEncode(tags)),
    ));
  }

  Stream<List<ArchiveEntry>> watchArchive([String query = '']) {
    final q = select(archiveEntries)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    final kw = query.trim();
    if (kw.isNotEmpty) {
      final like = '%$kw%';
      q.where(
        (t) =>
            t.title.like(like) |
            t.summary.like(like) |
            t.keyPointsJson.like(like),
      );
    }
    return q.watch();
  }

  Future<void> deleteArchiveEntry(int id) {
    return (delete(archiveEntries)..where((t) => t.id.equals(id))).go();
  }

  // ---------- 备份 ----------

  Future<List<Conversation>> getAllConversations() => select(conversations).get();
  Future<List<Message>> getAllMessages() => select(messages).get();
  Future<List<ArchiveEntry>> getAllArchive() => select(archiveEntries).get();

  Future<void> clearAll() async {
    await delete(archiveEntries).go();
    await delete(messages).go();
    await delete(conversations).go();
  }
}
