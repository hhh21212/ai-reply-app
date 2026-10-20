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

@DriftDatabase(tables: [Conversations, Messages, ArchiveEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 1;
}

QueryExecutor _open() {
  return driftDatabase(name: 'ai_reply');
}
