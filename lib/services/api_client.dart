import 'dart:async';
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
  static const _idleTimeout = Duration(seconds: 90);

  late final Dio _dio;

  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 3),
            ));

  /// 非流式请求，一次性返回完整文本（用于摘要抽取 / 测试连接）。
  Future<String> chatOnce(
    ApiConfig config,
    List<ChatMessage> messages, {
    String? system,
    bool jsonMode = false,
    CancelToken? cancelToken,
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

    final Map<String, dynamic>? data;
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        config.endpoint,
        data: body,
        cancelToken: cancelToken,
        options: Options(headers: {'Authorization': 'Bearer ${config.apiKey}'}),
      );
      data = resp.data;
    } on DioException catch (e) {
      throw _mapDio(e);
    }

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
  Stream<String> chatStream(
    ApiConfig config,
    List<ChatMessage> messages, {
    String? system,
    CancelToken? cancelToken,
  }) async* {
    final body = <String, dynamic>{
      'model': config.model,
      'messages': [
        if (system != null && system.isNotEmpty)
          {'role': 'system', 'content': system},
        ...messages.map((m) => m.toOpenAi()),
      ],
      'stream': true,
    };

    final Response<ResponseBody> resp;
    try {
      resp = await _dio.post<ResponseBody>(
        config.endpoint,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey}'},
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (e) {
      throw _mapDio(e);
    }

    final stream = resp.data!.stream;
    final lines = const LineSplitter().bind(utf8.decoder.bind(stream));
    try {
      await for (final line in lines.timeout(_idleTimeout)) {
        final content = _parseSseLine(line);
        if (content != null && content.isNotEmpty) yield content;
      }
    } on TimeoutException {
      throw ApiTimeoutException('流式响应长时间无数据');
    } on DioException catch (e) {
      throw _mapDio(e);
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
      final first = choices.first as Map<String, dynamic>;
      final delta = first['delta'] as Map<String, dynamic>?;
      final content = delta?['content'] as String?;
      if (content != null && content.isNotEmpty) return content;
      // 个别兼容端点可能一次返回完整 message，兜底取一下
      final message = first['message'] as Map<String, dynamic>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  static ApiException _mapDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return ApiCancelledException();
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiTimeoutException();
      case DioExceptionType.connectionError:
        return ApiNetworkException();
      case DioExceptionType.badResponse:
        return ApiHttpException(e.response?.statusCode, _httpMessage(e));
      case DioExceptionType.badCertificate:
        return ApiException('证书错误：${e.message}');
      case DioExceptionType.unknown:
        return ApiNetworkException();
    }
  }

  static String _httpMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] != null) return err['message'].toString();
      if (err is String && err.isNotEmpty) return err;
    }
    return e.message ?? '';
  }
}

/// API 请求异常的基类，带面向用户的中文友好提示。
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  String friendlyMessage() => message;

  @override
  String toString() => message;
}

class ApiTimeoutException extends ApiException {
  ApiTimeoutException([super.message = '请求超时']);

  @override
  String friendlyMessage() => '请求超时，请检查网络后重试';
}

class ApiNetworkException extends ApiException {
  ApiNetworkException([super.message = '网络错误']);

  @override
  String friendlyMessage() => '网络连接失败，请检查网络';
}

class ApiHttpException extends ApiException {
  final int? statusCode;
  ApiHttpException(this.statusCode, [super.message = '接口返回错误']);

  @override
  String friendlyMessage() {
    if (statusCode == 401) return '接口返回 401：API Key 可能无效';
    if (statusCode == 429) return '请求过于频繁（429），请稍后再试';
    if (statusCode != null && statusCode! >= 500) {
      return '服务端错误（$statusCode），请稍后再试';
    }
    return '接口返回错误（$statusCode）${message.isNotEmpty ? '：$message' : ''}';
  }
}

class ApiCancelledException extends ApiException {
  ApiCancelledException([super.message = '已取消']);

  @override
  String friendlyMessage() => '已取消';
}
