import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends AsyncNotifier<AppSettings> {
  SettingsService get _svc => ref.read(settingsServiceProvider);

  @override
  Future<AppSettings> build() => _svc.load();

  Future<void> save(AppSettings s) async {
    await _svc.save(s);
    state = AsyncData(s);
  }

  Future<String> testConnection(AppSettings s) async {
    final client = ref.read(apiClientProvider);
    try {
      await client.chatOnce(
        s.toApiConfig(),
        const [ChatMessage('user', '请只回复两个字：OK')],
        system: '你是连接测试助手，收到任何输入都只回复"OK"。',
      );
      return '连接成功';
    } catch (e) {
      return '连接失败：$e';
    }
  }
}
