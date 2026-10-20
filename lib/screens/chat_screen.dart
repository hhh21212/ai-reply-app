import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';
import '../providers/chat_provider.dart';
import '../providers/archive_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_client.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  int? _conversationId;
  List<Message> _messages = [];
  String _streaming = '';
  bool _sending = false;
  bool _archiving = false;
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

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadConversation(int id) async {
    final db = ref.read(databaseProvider);
    final msgs = await db.getMessages(id);
    if (!mounted) return;
    setState(() {
      _conversationId = id;
      _messages = msgs;
      _streaming = '';
    });
    _scrollToBottom();
  }

  Future<void> _newConversation() async {
    final conv = await ref.read(databaseProvider).createConversation();
    if (!mounted) return;
    setState(() {
      _conversationId = conv.id;
      _messages = [];
      _streaming = '';
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings == null || !settings.isConfigured) {
      _showSnack('请先在「设置」页配置 API 地址与 Key');
      return;
    }
    final db = ref.read(databaseProvider);
    final api = ref.read(apiClientProvider);

    _inputController.clear();
    final convId = _conversationId ?? (await db.createConversation()).id;
    if (_conversationId == null && mounted) {
      setState(() => _conversationId = convId);
    }

    final userMsg = await db.addMessage(convId, 'user', text);
    await db.touchConversation(convId);
    if (!mounted) return;
    setState(() {
      _messages = [..._messages, userMsg];
      _streaming = '';
      _sending = true;
    });
    _scrollToBottom();

    final apiMessages =
        _messages.map((m) => ChatMessage(m.role, m.content)).toList();

    final buffer = StringBuffer();
    try {
      await for (final chunk
          in api.chatStream(settings.toApiConfig(), apiMessages)) {
        buffer.write(chunk);
        if (mounted) setState(() => _streaming = buffer.toString());
      }
      final full = buffer.toString();
      if (full.isNotEmpty) {
        final assistantMsg = await db.addMessage(convId, 'assistant', full);
        if (mounted) {
          setState(() => _messages = [..._messages, assistantMsg]);
        }
      }
    } catch (e) {
      _showSnack('请求失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _streaming = '';
          _sending = false;
        });
      }
      _scrollToBottom();
    }
  }

  Future<void> _archive() async {
    if (_archiving) return;
    if (_messages.isEmpty) {
      _showSnack('当前没有可归档的对话');
      return;
    }
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings == null || !settings.isConfigured) {
      _showSnack('请先在「设置」页配置 API');
      return;
    }
    setState(() => _archiving = true);
    final db = ref.read(databaseProvider);
    final summaryService = ref.read(summaryServiceProvider);
    final apiMessages =
        _messages.map((m) => ChatMessage(m.role, m.content)).toList();
    try {
      final result =
          await summaryService.summarize(settings.toApiConfig(), apiMessages);
      await db.addArchiveEntry(
        conversationId: _conversationId,
        title: result.title,
        summary: result.summary,
        keyPoints: result.keyPoints,
        tags: result.tags,
      );
      if (_conversationId != null) {
        await db.setConversationTitle(_conversationId!, result.title);
        await db.setConversationArchived(_conversationId!, true);
      }
      if (mounted) {
        setState(() {
          _conversationId = null;
          _messages = [];
          _streaming = '';
        });
        _showSnack('已归档到档案');
      }
    } catch (e) {
      _showSnack('归档失败：$e');
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  String _titleOf(List<Conversation> list) {
    final id = _conversationId;
    if (id == null) return '新对话';
    for (final c in list) {
      if (c.id == id) return c.title;
    }
    return '对话';
  }

  @override
  Widget build(BuildContext context) {
    final conversations =
        ref.watch(conversationsProvider).valueOrNull ?? const <Conversation>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleOf(conversations)),
        actions: [
          IconButton(
            tooltip: '归档本次对话',
            onPressed: _archiving ? null : _archive,
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: '新对话',
            onPressed: _sending ? null : _newConversation,
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
        currentId: _conversationId,
        onSelect: (id) {
          Navigator.pop(context);
          _loadConversation(id);
        },
        onDelete: (id) async {
          await ref.read(databaseProvider).deleteConversation(id);
          if (id == _conversationId && mounted) {
            setState(() {
              _conversationId = null;
              _messages = [];
              _streaming = '';
            });
          }
        },
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && _streaming.isEmpty
                ? const Center(child: Text('开始一段新对话吧'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        _messages.length + (_streaming.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i < _messages.length) {
                        final m = _messages[i];
                        return MessageBubble(role: m.role, content: m.content);
                      }
                      return MessageBubble(
                        role: 'assistant',
                        content: _streaming,
                        streaming: true,
                      );
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
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
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
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
  final void Function(int id) onSelect;
  final void Function(int id) onDelete;

  const _ConversationDrawer({
    required this.conversations,
    required this.currentId,
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
                            onPressed: () => onDelete(c.id),
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
