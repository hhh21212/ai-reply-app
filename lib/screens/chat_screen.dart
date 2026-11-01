import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';
import '../providers/archive_provider.dart';
import '../providers/chat_controller.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  void _clearReference() {
    ref.read(activeArchiveRefProvider.notifier).state = null;
    ref.read(activeSourceArchiveIdProvider.notifier).state = null;
  }

  Future<void> _onArchive() async {
    final sourceRef = ref.read(activeArchiveRefProvider);
    final sourceId = ref.read(activeSourceArchiveIdProvider);

    if (sourceId != null && sourceRef != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('归档方式'),
          content: Text('本次对话引用了档案「${sourceRef.title}」。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'new'),
              child: const Text('新建档案'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('合并到原档案'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      ref
          .read(chatControllerProvider.notifier)
          .archive(action: choice == 'merge'
              ? ArchiveAction.mergeToSource
              : ArchiveAction.newEntry);
      return;
    }

    ref.read(chatControllerProvider.notifier).archive();
  }

  String _titleOf(List<Conversation> list, int? id) {
    if (id == null) return '新对话';
    for (final c in list) {
      if (c.id == id) return c.title;
    }
    return '对话';
  }

  Widget _buildReferenceCard(ArchiveRef ar) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.link, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已引用档案：${ar.title}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ar.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '取消引用',
              icon: const Icon(Icons.close),
              onPressed: _clearReference,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ChatState chat) {
    final canRetry = chat.messages.isNotEmpty;
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chat.errorText ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canRetry)
              TextButton(
                onPressed: () =>
                    ref.read(chatControllerProvider.notifier).regenerate(),
                child: const Text('重试'),
              ),
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).clearError(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final conversations =
        ref.watch(conversationsProvider).valueOrNull ?? const <Conversation>[];
    final activeRef = ref.watch(activeArchiveRefProvider);

    ref.listen(chatControllerProvider, (prev, next) {
      if (next.streaming.length != (prev?.streaming.length ?? 0) ||
          next.messages.length != (prev?.messages.length ?? 0)) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleOf(conversations, chat.conversationId)),
        actions: [
          IconButton(
            tooltip: '归档本次对话',
            onPressed: chat.archiving ? null : _onArchive,
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: '新对话',
            onPressed: chat.sending
                ? null
                : () => ref.read(chatControllerProvider.notifier).newConversation(),
            icon: const Icon(Icons.add_comment_outlined),
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: '会话列表',
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ],
      ),
      drawer: _ConversationDrawer(
        conversations: conversations,
        currentId: chat.conversationId,
        enabled: !chat.sending,
        onSelect: (id) {
          Navigator.pop(context);
          ref.read(chatControllerProvider.notifier).loadConversation(id);
        },
        onDelete: (id) async {
          await ref.read(databaseProvider).deleteConversation(id);
          if (id == chat.conversationId) {
            ref.read(chatControllerProvider.notifier).reset();
          }
        },
      ),
      body: Column(
        children: [
          if (activeRef != null) _buildReferenceCard(activeRef),
          if (chat.errorText != null) _buildErrorBanner(chat),
          Expanded(
            child: chat.messages.isEmpty && chat.streaming.isEmpty
                ? const Center(child: Text('开始一段新对话吧'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        chat.messages.length + (chat.streaming.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i < chat.messages.length) {
                        final m = chat.messages[i];
                        final isLastAssistant = m.role == 'assistant' &&
                            i == chat.messages.length - 1;
                        return MessageBubble(
                          role: m.role,
                          content: m.content,
                          onRegenerate: isLastAssistant
                              ? () => ref
                                  .read(chatControllerProvider.notifier)
                                  .regenerate()
                              : null,
                        );
                      }
                      return MessageBubble(
                        role: 'assistant',
                        content: chat.streaming,
                        streaming: true,
                      );
                    },
                  ),
          ),
          _buildInputBar(chat),
        ],
      ),
    );
  }

  Widget _buildInputBar(ChatState chat) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '输入消息…',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: chat.sending ? null : (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            chat.sending
                ? IconButton.filled(
                    tooltip: '停止生成',
                    onPressed: () =>
                        ref.read(chatControllerProvider.notifier).cancelSend(),
                    icon: const Icon(Icons.stop),
                  )
                : IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
          ],
        ),
      ),
    );
  }
}

class _ConversationDrawer extends StatelessWidget {
  final List<Conversation> conversations;
  final int? currentId;
  final bool enabled;
  final void Function(int id) onSelect;
  final void Function(int id) onDelete;

  const _ConversationDrawer({
    required this.conversations,
    required this.currentId,
    required this.enabled,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '会话',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: conversations.isEmpty
                  ? const Center(child: Text('暂无会话'))
                  : ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, i) {
                        final c = conversations[i];
                        return ListTile(
                          selected: c.id == currentId,
                          enabled: enabled,
                          leading: Icon(
                            c.archived
                                ? Icons.archive
                                : Icons.chat_bubble_outline,
                          ),
                          title: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_formatTime(c.updatedAt)),
                          onTap: () => onSelect(c.id),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: enabled ? () => onDelete(c.id) : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
  }
}
