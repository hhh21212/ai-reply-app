import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers/archive_provider.dart';
import '../providers/chat_provider.dart';

class ArchiveDetailScreen extends ConsumerWidget {
  final int entryId;
  const ArchiveDetailScreen({super.key, required this.entryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(archiveEntriesProvider).valueOrNull ?? const <ArchiveEntry>[];
    ArchiveEntry? entry;
    for (final e in entries) {
      if (e.id == entryId) {
        entry = e;
        break;
      }
    }

    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('档案不存在')),
      );
    }

    final keyPoints = _decodeList(entry.keyPointsJson);
    final tags = _decodeList(entry.tagsJson);
    final conversationId = entry.conversationId;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title),
        actions: [
          IconButton(
            tooltip: '调用到对话',
            icon: const Icon(Icons.input),
            onPressed: () {
              referenceArchiveToChat(ref, entry!);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            entry.summary,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 16),
          if (keyPoints.isNotEmpty) ...[
            Text('关键信息', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final k in keyPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(k)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (tags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final t in tags) Chip(label: Text('#$t'))],
            ),
            const SizedBox(height: 8),
          ],
          Text(
            '归档时间：${entry.createdAt}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (conversationId != null) ...[
            const SizedBox(height: 16),
            Text('原始对话', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ConversationView(conversationId: conversationId),
          ],
        ],
      ),
    );
  }

  List<String> _decodeList(String json) {
    try {
      final v = jsonDecode(json);
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }
}

class _ConversationView extends ConsumerWidget {
  final int conversationId;
  const _ConversationView({required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgs =
        ref.watch(messagesProvider(conversationId)).valueOrNull ??
            const <Message>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in msgs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    m.role == 'user' ? '我' : 'AI',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: Text(m.content)),
              ],
            ),
          ),
      ],
    );
  }
}
