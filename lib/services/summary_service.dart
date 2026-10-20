import 'dart:convert';

import 'api_client.dart';

class SummaryResult {
  final String title;
  final String summary;
  final List<String> keyPoints;
  final List<String> tags;
  const SummaryResult({
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.tags,
  });
}

class SummaryService {
  final ApiClient _client;
  SummaryService(this._client);

  static const _systemPrompt = '你是对话归档助手。请阅读下面的对话，提取关键信息，'
      '只输出一个 JSON 对象（不要输出任何其它文字、不要用代码块包裹），格式如下：\n'
      '{"title": "不超过20字的中文标题", "summary": "2-4句话概括这次对话", '
      '"keyPoints": ["关键信息1", "关键信息2"], "tags": ["标签1"]}\n'
      '要求：keyPoints 3-8 条；tags 0-5 个；全部用中文。';

  Future<SummaryResult> summarize(
    ApiConfig config,
    List<ChatMessage> messages,
  ) async {
    String raw;
    try {
      raw = await _client.chatOnce(
        config,
        messages,
        system: _systemPrompt,
        jsonMode: true,
      );
    } catch (_) {
      // 某些兼容端点不支持 response_format，退回普通模式再试一次
      raw = await _client.chatOnce(config, messages, system: _systemPrompt);
    }
    return parseSummary(raw);
  }

  /// 从模型输出中稳健地解析摘要 JSON；失败时用原文兜底。
  static SummaryResult parseSummary(String raw) {
    final trimmed = raw.trim();
    String? jsonStr;

    if (trimmed.startsWith('{')) {
      jsonStr = trimmed;
    } else {
      final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
      if (fence != null) {
        jsonStr = fence.group(1)!.trim();
      } else {
        final start = trimmed.indexOf('{');
        final end = trimmed.lastIndexOf('}');
        if (start >= 0 && end > start) {
          jsonStr = trimmed.substring(start, end + 1);
        }
      }
    }

    if (jsonStr != null) {
      try {
        final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
        final title = (obj['title'] as String?)?.trim() ?? '';
        final summary = (obj['summary'] as String?)?.trim() ?? '';
        final keyPoints = _toStringList(obj['keyPoints'] ?? obj['key_points']);
        final tags = _toStringList(obj['tags']);
        return SummaryResult(
          title: title.isNotEmpty ? title : '未命名',
          summary: summary,
          keyPoints: keyPoints,
          tags: tags,
        );
      } catch (_) {
        // 落到兜底
      }
    }

    return SummaryResult(
      title: '未命名',
      summary: trimmed,
      keyPoints: const [],
      tags: const [],
    );
  }

  static List<String> _toStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      return [v.trim()];
    }
    return const [];
  }
}
