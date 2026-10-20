import 'dart:convert';

import '../data/database.dart';
import '../data/dao.dart';

class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  /// 生成完整 JSON 备份（不含 API Key）。
  Future<String> buildJson() async {
    final conversations = await db.getAllConversations();
    final messages = await db.getAllMessages();
    final archive = await db.getAllArchive();

    final byConv = <int, List<Map<String, dynamic>>>{};
    for (final m in messages) {
      byConv.putIfAbsent(m.conversationId, () => []).add({
        'role': m.role,
        'content': m.content,
        'createdAt': m.createdAt.toIso8601String(),
      });
    }

    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'conversations': conversations.map((c) {
        return {
          'title': c.title,
          'archived': c.archived,
          'createdAt': c.createdAt.toIso8601String(),
          'messages': byConv[c.id] ?? [],
        };
      }).toList(),
      'archive': archive.map((a) {
        return {
          'title': a.title,
          'summary': a.summary,
          'keyPoints': _decode(a.keyPointsJson),
          'tags': _decode(a.tagsJson),
          'createdAt': a.createdAt.toIso8601String(),
        };
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 生成档案的 Markdown 备份。
  Future<String> buildMarkdown() async {
    final archive = await db.getAllArchive();
    final b = StringBuffer()..writeln('# 对话档案\n');
    for (final a in archive) {
      b.writeln('## ${a.title}');
      b.writeln('*${a.createdAt}*\n');
      b.writeln(a.summary);
      b.writeln();
      final keyPoints = _decode(a.keyPointsJson);
      if (keyPoints.isNotEmpty) {
        b.writeln('**关键信息**');
        for (final k in keyPoints) {
          b.writeln('- $k');
        }
        b.writeln();
      }
      final tags = _decode(a.tagsJson);
      if (tags.isNotEmpty) {
        b.writeln('标签：${tags.map((t) => '#$t').join(' ')}\n');
      }
      b.writeln('---\n');
    }
    return b.toString();
  }

  Future<void> importJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final conversations =
        (data['conversations'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final c in conversations) {
      final title = (c['title'] as String?) ?? '新对话';
      final conv = await db.createConversation(title: title);
      final msgs = (c['messages'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final m in msgs) {
        final role = m['role'] as String? ?? 'user';
        final content = m['content'] as String? ?? '';
        await db.addMessage(conv.id, role, content);
      }
    }
    final archive = (data['archive'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final a in archive) {
      await db.addArchiveEntry(
        title: (a['title'] as String?) ?? '未命名',
        summary: (a['summary'] as String?) ?? '',
        keyPoints: _toStrList(a['keyPoints']),
        tags: _toStrList(a['tags']),
      );
    }
  }

  Future<void> clearAll() => db.clearAll();

  static List<String> _decode(String json) => _toStrList(
        (() {
          try {
            return jsonDecode(json);
          } catch (_) {
            return const [];
          }
        })(),
      );

  static List<String> _toStrList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }
}
