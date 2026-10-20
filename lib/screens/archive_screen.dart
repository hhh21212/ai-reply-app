import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';
import '../providers/archive_provider.dart';
import '../providers/chat_provider.dart';
import 'archive_detail_screen.dart';

class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(archiveEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('档案'), centerTitle: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索标题 / 摘要 / 关键信息…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(archiveSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (entries) {
                if (entries.isEmpty) {
                  return const Center(child: Text('暂无档案，去聊天页归档一次对话吧'));
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      title: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        e.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _formatTime(e.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArchiveDetailScreen(entryId: e.id),
                        ),
                      ),
                      onLongPress: () => _confirmDelete(context, ref, e),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ArchiveEntry e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除档案'),
        content: Text('确定删除「${e.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deleteArchiveEntry(e.id);
    }
  }

  String _formatTime(DateTime t) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)}';
  }
}
