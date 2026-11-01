import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant('新对话'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId => integer()();
  TextColumn get role => text()(); // 'user' | 'assistant'
  TextColumn get content => text()();
  TextColumn get status => text().withDefault(const Constant('ok'))(); // 'ok' | 'partial' | 'error'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class ArchiveEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get summary => text()();
  TextColumn get keyPointsJson => text().withDefault(const Constant('[]'))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 多套 API 配置的元数据（API Key 单独存 secure storage，键名 api_key_{id}）。
class ApiProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get model => text()();
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Conversations, Messages, ArchiveEntries, ApiProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(apiProfiles);
            await m.addColumn(messages, messages.status);
          }
          await _createIndexes(m);
        },
      );
}

/// 建立常用索引（幂等，onCreate 与 onUpgrade 都会调用）。
Future<void> _createIndexes(Migrator m) async {
  await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at)');
  await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at)');
  await m.database.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_archive_created ON archive_entries(created_at)');
}

QueryExecutor _open() {
  return driftDatabase(name: 'ai_reply');
}
