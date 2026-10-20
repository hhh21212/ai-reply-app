import 'dart:convert';

import 'package:dio/dio.dart';

/// 一条对话消息（OpenAI 兼容格式的 role/content）。
class ChatMessage {
  final String role; // 'system' | 'user' | 'assistant'
  final String content;
  const ChatMessage(this.role, this.content);

  Map<String, dynamic> toOpenAi() => {'role': role, 'content': content};
}

/// 可配置的 API 连接信息。
class ApiConfig {
  final String baseUrl;
  final String model;
  final String apiKey;
  const ApiConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  bool get isConfigured => apiKey.trim().isNotEmpty;

  String get endpoint =>
      '${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions';
}

/// OpenAI 兼容的对话客户端（覆盖 DeepSeek 及多数国内服务）。
class ApiClient {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 5),
  ));

  /// 非流式请求，一次性返回完整文本（用于摘要抽取 / 测试连接）。
  Future<String> chatOnce(
    ApiConfig config,
    List<ChatMessage> messages, {
    String? system,
    bool jsonMode = false,
  }) async {
    final body = <String, dynamic>{
      'model': config.model,
      'messages': [
        if (system != null && system.isNotEmpty)
          {'role': 'system', 'content': system},
        ...messages.map((m) => m.toOpenAi()),
      ],
      'stream': false,
    };
    if (jsonMode) {
      body['response_format'] = {'type': 'json_object'};
    }

    final resp = await _dio.post<Map<String, dynamic>>(
      config.endpoint,
      data: body,
      options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
    );

    final data = resp.data;
    final choices = data?['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw ApiException('响应缺少 choices: $data');
    }
    final content = choices.first['message']?['content'] as String?;
    if (content == null) {
      throw ApiException('响应缺少 content: $data');
    }
    return content;
  }

  /// 流式请求，逐段产出增量文本。
  Stream<String> chatStream(ApiConfig config, List<ChatMessage> messages) async* {
    final body = <String, dynamic>{
      'model': config.model,
      'messages': messages.map((m) => m.toOpenAi()).toList(),
      'stream': true,
    };

    final resp = await _dio.post<ResponseBody>(
      config.endpoint,
      data: body,
      options: Options(
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
        responseType: ResponseType.stream,
      ),
    );

    final stream = resp.data!.stream;
    final lines = const LineSplitter().bind(utf8.decoder.bind(stream));
    await for (final line in lines) {
      final content = _parseSseLine(line);
      if (content != null && content.isNotEmpty) yield content;
    }
  }

  /// 解析一行 SSE `data: ...`，返回增量内容；非数据行或结束标记返回 null。
  static String? _parseSseLine(String line) {
    final l = line.trim();
    if (!l.startsWith('data:')) return null;
    final payload = l.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final obj = jsonDecode(payload) as Map<String, dynamic>;
      final choices = obj['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final delta = choices.first['delta'] as Map<String, dynamic>?;
      final content = delta?['content'] as String?;
      return (content != null && content.isNotEmpty) ? content : null;
    } catch (_) {
      return null;
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
