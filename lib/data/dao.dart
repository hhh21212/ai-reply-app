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

  /// 更新消息状态（'ok' | 'partial' | 'error'），用于标记「出错保留的部分回答」。
  Future<void> updateMessageStatus(int id, String status) {
    return (update(messages)..where((t) => t.id.equals(id)))
        .write(MessagesCompanion(status: Value(status)));
  }

  Future<void> deleteMessage(int id) {
    return (delete(messages)..where((t) => t.id.equals(id))).go();
  }

  // ---------- 多 API 配置 ----------

  Future<List<ApiProfile>> getAllApiProfiles() {
    return (select(apiProfiles)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  Future<int> insertApiProfile({
    required String name,
    required String baseUrl,
    required String model,
    bool active = false,
    int sortOrder = 0,
  }) {
    return into(apiProfiles).insert(ApiProfilesCompanion.insert(
          name: name,
          baseUrl: baseUrl,
          model: model,
          active: Value(active),
          sortOrder: Value(sortOrder),
        ));
  }

  Future<void> updateApiProfile({
    required int id,
    String? name,
    String? baseUrl,
    String? model,
    bool? active,
    int? sortOrder,
  }) {
    return (update(apiProfiles)..where((t) => t.id.equals(id))).write(
          ApiProfilesCompanion(
            name: name == null ? const Value.absent() : Value(name),
            baseUrl: baseUrl == null ? const Value.absent() : Value(baseUrl),
            model: model == null ? const Value.absent() : Value(model),
            active: active == null ? const Value.absent() : Value(active),
            sortOrder:
                sortOrder == null ? const Value.absent() : Value(sortOrder),
          ),
        );
  }

  Future<void> deleteApiProfile(int id) {
    return (delete(apiProfiles)..where((t) => t.id.equals(id))).go();
  }

  /// 把 id 设为 active，其余全部取消 active。
  Future<void> setActiveApiProfile(int id) async {
    await (update(apiProfiles))
        .write(const ApiProfilesCompanion(active: Value(false)));
    await (update(apiProfiles)..where((t) => t.id.equals(id)))
        .write(const ApiProfilesCompanion(active: Value(true)));
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

  /// 把一次新对话的摘要/关键点追加写回某条既有档案（「拓展」）。
  Future<void> extendArchiveEntry({
    required int id,
    required String extraSummary,
    required List<String> extraKeyPoints,
    required List<String> extraTags,
  }) async {
    final existing = await (select(archiveEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) return;

    final oldKeyPoints = _decodeStringList(existing.keyPointsJson);
    final oldTags = _decodeStringList(existing.tagsJson);

    final mergedKeyPoints = <String>[...oldKeyPoints];
    for (final k in extraKeyPoints) {
      if (!mergedKeyPoints.contains(k)) mergedKeyPoints.add(k);
    }
    final mergedTags = <String>[...oldTags];
    for (final t in extraTags) {
      if (!mergedTags.contains(t)) mergedTags.add(t);
    }

    final parts = <String>[
      if (existing.summary.trim().isNotEmpty) existing.summary.trim(),
      if (extraSummary.trim().isNotEmpty) extraSummary.trim(),
    ];
    final mergedSummary = parts.join('\n\n—— 后续拓展 ——\n\n');

    await (update(archiveEntries)..where((t) => t.id.equals(id))).write(
      ArchiveEntriesCompanion(
        summary: Value(mergedSummary),
        keyPointsJson: Value(jsonEncode(mergedKeyPoints)),
        tagsJson: Value(jsonEncode(mergedTags)),
      ),
    );
  }

  List<String> _decodeStringList(String json) {
    try {
      final v = jsonDecode(json);
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
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
