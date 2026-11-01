import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';
import '../services/api_client.dart';
import '../services/settings_service.dart';
import '../services/summary_service.dart';
import 'archive_provider.dart';
import 'chat_provider.dart';
import 'settings_provider.dart';

/// 归档动作：新建一条档案，或合并回被引用的来源档案。
enum ArchiveAction { newEntry, mergeToSource }

/// 聊天页的完整状态。
class ChatState {
  final int? conversationId;
  final List<Message> messages;
  final String streaming;
  final bool sending;
  final bool archiving;
  final String? errorText;

  const ChatState({
    this.conversationId,
    this.messages = const [],
    this.streaming = '',
    this.sending = false,
    this.archiving = false,
    this.errorText,
  });

  static const Object _unset = Object();

  ChatState copyWith({
    int? conversationId,
    List<Message>? messages,
    String? streaming,
    bool? sending,
    bool? archiving,
    Object? errorText = _unset,
  }) =>
      ChatState(
        conversationId: conversationId ?? this.conversationId,
        messages: messages ?? this.messages,
        streaming: streaming ?? this.streaming,
        sending: sending ?? this.sending,
        archiving: archiving ?? this.archiving,
        errorText:
            identical(errorText, _unset) ? this.errorText : errorText as String?,
      );
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  CancelToken? _cancelToken;

  @override
  ChatState build() => const ChatState();

  AppDatabase get _db => ref.read(databaseProvider);

  ApiProfileModel? _activeProfile() =>
      ref.read(settingsControllerProvider).valueOrNull?.active;

  void _clearReference() {
    ref.read(activeArchiveRefProvider.notifier).state = null;
    ref.read(activeSourceArchiveIdProvider.notifier).state = null;
  }

  // ---------- 会话 ----------

  Future<void> loadConversation(int id) async {
    final msgs = await _db.getMessages(id);
    _clearReference();
    state = ChatState(conversationId: id, messages: msgs);
  }

  Future<void> newConversation() async {
    final conv = await _db.createConversation();
    _clearReference();
    state = ChatState(conversationId: conv.id);
  }

  /// 清空当前会话（删除当前会话后回退到空状态）。
  void reset() {
    _clearReference();
    state = const ChatState();
  }

  /// 关闭错误提示横幅。
  void clearError() => state = state.copyWith(errorText: null);

  // ---------- 发送 / 取消 / 重新生成 ----------

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;

    final active = _activeProfile();
    if (active == null || !active.isConfigured) {
      state = state.copyWith(errorText: '请先在「设置」页配置 API 地址与 Key');
      return;
    }

    final db = _db;
    final api = ref.read(apiClientProvider);

    final convId = state.conversationId ?? (await db.createConversation()).id;
    final userMsg = await db.addMessage(convId, 'user', trimmed);
    await db.touchConversation(convId);

    final base = [...state.messages, userMsg];
    state = state.copyWith(
      conversationId: convId,
      messages: base,
      sending: true,
      streaming: '',
      errorText: null,
    );

    await _stream(api, active.toApiConfig(), base, convId);
  }

  /// 取消正在进行的生成；已生成的部分会保留下来（标记 partial）。
  Future<void> cancelSend() async {
    _cancelToken?.cancel();
  }

  /// 重新生成最后一条 AI 回答（也用于出错后的「重试」）。
  Future<void> regenerate() async {
    if (state.sending) return;

    final active = _activeProfile();
    if (active == null || !active.isConfigured) {
      state = state.copyWith(errorText: '请先在「设置」页配置 API 地址与 Key');
      return;
    }
    final convId = state.conversationId;
    if (convId == null) return;

    final msgs = [...state.messages];
    int lastAssistant = -1;
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'assistant') {
        lastAssistant = i;
        break;
      }
    }

    // 没有 AI 回答（上次完全失败、无部分内容）：重发最后一条用户消息。
    if (lastAssistant < 0) {
      if (msgs.isEmpty || msgs.last.role != 'user') return;
      final lastUser = msgs.removeLast();
      await _db.deleteMessage(lastUser.id);
      final reAdded = await _db.addMessage(convId, 'user', lastUser.content);
      await _db.touchConversation(convId);
      final base = [...msgs, reAdded];
      state = state.copyWith(
        messages: base,
        sending: true,
        streaming: '',
        errorText: null,
      );
      await _stream(
          ref.read(apiClientProvider), active.toApiConfig(), base, convId);
      return;
    }

    final removed = msgs.removeAt(lastAssistant);
    await _db.deleteMessage(removed.id);

    state = state.copyWith(
      messages: msgs,
      sending: true,
      streaming: '',
      errorText: null,
    );
    await _stream(
        ref.read(apiClientProvider), active.toApiConfig(), msgs, convId);
  }

  Future<void> _stream(
    ApiClient api,
    ApiConfig config,
    List<Message> base,
    int convId,
  ) async {
    final db = _db;
    final activeRef = ref.read(activeArchiveRefProvider);
    final apiMessages = [
      if (activeRef != null)
        ChatMessage(
          'system',
          '以下是用户从档案中引用的历史内容，请基于它并结合用户的问题回答：\n${activeRef.content}',
        ),
      ...base.map((m) => ChatMessage(m.role, m.content)),
    ];

    final token = CancelToken();
    _cancelToken = token;
    final buffer = StringBuffer();

    try {
      await for (final chunk
          in api.chatStream(config, apiMessages, cancelToken: token)) {
        buffer.write(chunk);
        state = state.copyWith(streaming: buffer.toString());
      }
      final full = buffer.toString();
      if (full.isNotEmpty) {
        final assistantMsg = await db.addMessage(convId, 'assistant', full);
        state = state.copyWith(
          messages: [...base, assistantMsg],
          streaming: '',
        );
      } else {
        state = state.copyWith(streaming: '');
      }
    } on ApiCancelledException {
      await _persistPartial(db, base, convId, buffer.toString(), 'partial');
    } on ApiException catch (e) {
      await _persistPartial(db, base, convId, buffer.toString(), 'error',
          errorText: e.friendlyMessage());
    } catch (e) {
      await _persistPartial(db, base, convId, buffer.toString(), 'error',
          errorText: '请求失败：$e');
    } finally {
      _cancelToken = null;
      state = state.copyWith(sending: false);
    }
  }

  /// 出错/取消时：若已生成部分内容则落库保留，否则仅清空 streaming。
  Future<void> _persistPartial(
    AppDatabase db,
    List<Message> base,
    int convId,
    String partial,
    String status, {
    String? errorText,
  }) async {
    if (partial.isNotEmpty) {
      final assistantMsg = await db.addMessage(convId, 'assistant', partial);
      await db.updateMessageStatus(assistantMsg.id, status);
      state = state.copyWith(
        messages: [...base, assistantMsg],
        streaming: '',
        errorText: errorText,
      );
    } else {
      state = state.copyWith(streaming: '', errorText: errorText);
    }
  }

  // ---------- 归档 ----------

  Future<void> archive({ArchiveAction action = ArchiveAction.newEntry}) async {
    if (state.archiving) return;
    if (state.messages.isEmpty) {
      state = state.copyWith(errorText: '当前没有可归档的对话');
      return;
    }
    final active = _activeProfile();
    if (active == null || !active.isConfigured) {
      state = state.copyWith(errorText: '请先在「设置」页配置 API');
      return;
    }

    final db = _db;
    final summaryService = ref.read(summaryServiceProvider);
    final apiMessages =
        state.messages.map((m) => ChatMessage(m.role, m.content)).toList();

    state = state.copyWith(archiving: true);
    try {
      final result =
          await summaryService.summarize(active.toApiConfig(), apiMessages);

      if (action == ArchiveAction.mergeToSource) {
        final sourceId = ref.read(activeSourceArchiveIdProvider);
        if (sourceId != null) {
          await db.extendArchiveEntry(
            id: sourceId,
            extraSummary: result.summary,
            extraKeyPoints: result.keyPoints,
            extraTags: result.tags,
          );
        } else {
          await _addArchiveEntry(db, result);
        }
      } else {
        await _addArchiveEntry(db, result);
      }

      if (state.conversationId != null) {
        await db.setConversationTitle(state.conversationId!, result.title);
        await db.setConversationArchived(state.conversationId!, true);
      }
      _clearReference();
      state = const ChatState();
    } on ApiException catch (e) {
      state = state.copyWith(errorText: '归档失败：${e.friendlyMessage()}');
    } catch (e) {
      state = state.copyWith(errorText: '归档失败：$e');
    } finally {
      state = state.copyWith(archiving: false);
    }
  }

  Future<void> _addArchiveEntry(AppDatabase db, SummaryResult result) {
    return db.addArchiveEntry(
      conversationId: state.conversationId,
      title: result.title,
      summary: result.summary,
      keyPoints: result.keyPoints,
      tags: result.tags,
    );
  }
}
