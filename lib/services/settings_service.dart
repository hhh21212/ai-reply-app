import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dao.dart';
import '../data/database.dart';
import 'api_client.dart';

/// 一套 API 配置（面向 UI 的完整模型，含 Key）。
class ApiProfileModel {
  final int? id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;
  final bool active;
  final int sortOrder;

  const ApiProfileModel({
    this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.active = false,
    this.sortOrder = 0,
  });

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  ApiConfig toApiConfig() =>
      ApiConfig(baseUrl: baseUrl, model: model, apiKey: apiKey);

  ApiProfileModel copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
    bool? active,
    int? sortOrder,
  }) =>
      ApiProfileModel(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        active: active ?? this.active,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class SettingsService {
  static const _kThemeMode = 'theme_mode';
  static const _kMigratedV2 = 'migrated_v2';
  static const defaultBaseUrl = 'https://api.deepseek.com/v1';
  static const defaultModel = 'deepseek-v4-pro';

  final AppDatabase _db;
  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  SettingsService(this._db, this._secure, this._prefs);

  // ---------- API 配置 ----------

  Future<List<ApiProfileModel>> loadProfiles() async {
    await _migrateLegacy();
    final rows = await _db.getAllApiProfiles();
    final out = <ApiProfileModel>[];
    for (final r in rows) {
      final key = await _secure.read(key: 'api_key_${r.id}') ?? '';
      out.add(ApiProfileModel(
        id: r.id,
        name: r.name,
        baseUrl: r.baseUrl,
        model: r.model,
        apiKey: key,
        active: r.active,
        sortOrder: r.sortOrder,
      ));
    }
    return out;
  }

  Future<ApiProfileModel?> loadActiveProfile() async {
    final profiles = await loadProfiles();
    for (final p in profiles) {
      if (p.active) return p;
    }
    return profiles.isNotEmpty ? profiles.first : null;
  }

  /// 新建或更新一套配置；返回其 id。若标记为 active，则取消其它配置的 active。
  Future<int> saveProfile(ApiProfileModel p) async {
    final name = p.name.trim().isEmpty ? '未命名' : p.name.trim();
    final baseUrl = p.baseUrl.trim();
    final model = p.model.trim();

    final int id;
    if (p.id == null) {
      id = await _db.insertApiProfile(
        name: name,
        baseUrl: baseUrl,
        model: model,
        active: p.active,
        sortOrder: p.sortOrder,
      );
    } else {
      id = p.id!;
      await _db.updateApiProfile(
        id: id,
        name: name,
        baseUrl: baseUrl,
        model: model,
        active: p.active,
        sortOrder: p.sortOrder,
      );
    }

    if (p.apiKey.trim().isNotEmpty) {
      await _secure.write(key: 'api_key_$id', value: p.apiKey.trim());
    }
    if (p.active) {
      await _db.setActiveApiProfile(id);
    }
    return id;
  }

  Future<void> setActiveProfile(int id) => _db.setActiveApiProfile(id);

  Future<void> deleteProfile(int id) async {
    await _db.deleteApiProfile(id);
    await _secure.delete(key: 'api_key_$id');
  }

  // ---------- 外观 ----------

  Future<ThemeMode> loadThemeMode() async {
    final v = _prefs.getString(_kThemeMode);
    return ThemeMode.values.firstWhere(
      (m) => m.name == v,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  // ---------- 旧单配置迁移（一次） ----------

  Future<void> _migrateLegacy() async {
    if (_prefs.getBool(_kMigratedV2) == true) return;
    final existing = await _db.getAllApiProfiles();
    if (existing.isNotEmpty) {
      await _prefs.setBool(_kMigratedV2, true);
      return;
    }

    final oldBase = _prefs.getString('base_url');
    final oldModel = _prefs.getString('model');
    final oldKey = await _secure.read(key: 'api_key');
    final hasOld = oldBase != null ||
        oldModel != null ||
        (oldKey != null && oldKey.isNotEmpty);

    if (hasOld) {
      final id = await _db.insertApiProfile(
        name: '默认',
        baseUrl: (oldBase ?? defaultBaseUrl).trim(),
        model: (oldModel ?? defaultModel).trim(),
        active: true,
      );
      await _db.setActiveApiProfile(id);
      if (oldKey != null && oldKey.isNotEmpty) {
        await _secure.write(key: 'api_key_$id', value: oldKey);
      }
    }
    await _prefs.setBool(_kMigratedV2, true);
  }
}
