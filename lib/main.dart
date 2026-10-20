import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_shell.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final prefs = await SharedPreferences.getInstance();
  const secure = FlutterSecureStorage();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsServiceProvider.overrideWithValue(SettingsService(secure, prefs)),
      ],
      child: const AiReplyApp(),
    ),
  );
}

class AiReplyApp extends StatelessWidget {
  const AiReplyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 应答助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}
