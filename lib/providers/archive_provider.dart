import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';
import '../services/summary_service.dart';
import 'chat_provider.dart';
import 'settings_provider.dart';

final summaryServiceProvider = Provider<SummaryService>(
  (ref) => SummaryService(ref.watch(apiClientProvider)),
);

final archiveSearchProvider = StateProvider<String>((ref) => '');

final archiveEntriesProvider = StreamProvider<List<ArchiveEntry>>((ref) {
  final q = ref.watch(archiveSearchProvider);
  return ref.watch(databaseProvider).watchArchive(q);
});

/// 被「调用」到当前对话的一条档案引用（只读，不落库）。
class ArchiveRef {
  final String title;
  final String content; // 摘要 + 关键点拼成的纯文本
  const ArchiveRef({required this.title, required this.content});
}

/// 当前对话引用的档案内容（非空时聊天页显示引用卡片并注入上下文）。
final activeArchiveRefProvider = StateProvider<ArchiveRef?>((ref) => null);

/// 当前对话引用的来源档案 id，归档时据此提供「合并回原档案」选项。
final activeSourceArchiveIdProvider = StateProvider<int?>((ref) => null);

List<String> _decodeList(String json) {
  try {
    final v = jsonDecode(json);
    if (v is List) {
      return v.map((e) => e.toString()).toList();
    }
  } catch (_) {}
  return const [];
}

/// 把档案条目拼成引用文本（摘要 + 关键信息）。
ArchiveRef buildArchiveRef(ArchiveEntry e) {
  final keyPoints = _decodeList(e.keyPointsJson);
  final buf = StringBuffer();
  if (e.summary.trim().isNotEmpty) {
    buf.writeln(e.summary.trim());
  }
  if (keyPoints.isNotEmpty) {
    buf.writeln();
    buf.writeln('关键信息：');
    for (final k in keyPoints) {
      buf.writeln('• $k');
    }
  }
  return ArchiveRef(title: e.title, content: buf.toString().trim());
}

/// 把档案「调用」进当前对话：设置引用 + 记住来源 + 跳到聊天 Tab。
void referenceArchiveToChat(WidgetRef ref, ArchiveEntry e) {
  ref.read(activeArchiveRefProvider.notifier).state = buildArchiveRef(e);
  ref.read(activeSourceArchiveIdProvider.notifier).state = e.id;
  ref.read(homeTabProvider.notifier).state = 0;
}
