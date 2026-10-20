import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// 应用的 API 配置（Key 只保存在内存 / 安全存储中）。
class AppSettings {
  final String baseUrl;
  final String model;
  final String apiKey;
  const AppSettings({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  bool get isConfigured => apiKey.trim().isNotEmpty;

  ApiConfig toApiConfig() =>
      ApiConfig(baseUrl: baseUrl, model: model, apiKey: apiKey);

  AppSettings copyWith({String? baseUrl, String? model, String? apiKey}) =>
      AppSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
      );
}

class SettingsService {
  static const _kBase = 'base_url';
  static const _kModel = 'model';
  static const _kKey = 'api_key';
  static const defaultBaseUrl = 'https://api.deepseek.com/v1';
  static const defaultModel = 'deepseek-v4-pro';

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  SettingsService(this._secure, this._prefs);

  Future<AppSettings> load() async {
    final base = _prefs.getString(_kBase) ?? defaultBaseUrl;
    final model = _prefs.getString(_kModel) ?? defaultModel;
    final key = await _secure.read(key: _kKey) ?? '';
    return AppSettings(baseUrl: base, model: model, apiKey: key);
  }

  Future<void> save(AppSettings s) async {
    await _prefs.setString(_kBase, s.baseUrl.trim());
    await _prefs.setString(_kModel, s.model.trim());
    await _secure.write(key: _kKey, value: s.apiKey.trim());
  }
}
