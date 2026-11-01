import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// 设置页的完整状态：多套 API 配置 + 当前激活配置 + 外观模式。
class SettingsState {
  final List<ApiProfileModel> profiles;
  final ApiProfileModel? active;
  final ThemeMode themeMode;

  const SettingsState({
    required this.profiles,
    this.active,
    required this.themeMode,
  });

  SettingsState copyWith({
    List<ApiProfileModel>? profiles,
    ApiProfileModel? active,
    ThemeMode? themeMode,
  }) =>
      SettingsState(
        profiles: profiles ?? this.profiles,
        active: active ?? this.active,
        themeMode: themeMode ?? this.themeMode,
      );
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
        SettingsController.new);

class SettingsController extends AsyncNotifier<SettingsState> {
  SettingsService get _svc => ref.read(settingsServiceProvider);

  Future<SettingsState> _load() async {
    final profiles = await _svc.loadProfiles();
    ApiProfileModel? active;
    for (final p in profiles) {
      if (p.active) {
        active = p;
        break;
      }
    }
    active ??= profiles.isNotEmpty ? profiles.first : null;
    final themeMode = await _svc.loadThemeMode();
    return SettingsState(profiles: profiles, active: active, themeMode: themeMode);
  }

  @override
  Future<SettingsState> build() => _load();

  Future<void> saveProfile(ApiProfileModel p) async {
    await _svc.saveProfile(p);
    state = AsyncData(await _load());
  }

  Future<void> setActive(int id) async {
    await _svc.setActiveProfile(id);
    state = AsyncData(await _load());
  }

  Future<void> deleteProfile(int id) async {
    await _svc.deleteProfile(id);
    state = AsyncData(await _load());
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _svc.saveThemeMode(mode);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(themeMode: mode));
    }
  }

  Future<String> testConnection(ApiProfileModel p) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.chatOnce(
        p.toApiConfig(),
        const [ChatMessage('user', '请只回复两个字：OK')],
        system: '你是连接测试助手，收到任何输入都只回复"OK"。',
      );
      return '连接成功';
    } on ApiException catch (e) {
      return '连接失败：${e.friendlyMessage()}';
    } catch (e) {
      return '连接失败：$e';
    }
  }
}
