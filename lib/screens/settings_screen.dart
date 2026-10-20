import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _baseController = TextEditingController();
  final _modelController = TextEditingController();
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  bool _busy = false;
  bool _loaded = false;

  @override
  void dispose() {
    _baseController.dispose();
    _modelController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置 · API 管理'), centerTitle: false),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (settings) {
          if (!_loaded) {
            _loaded = true;
            _baseController.text = settings.baseUrl;
            _modelController.text = settings.model;
            _keyController.text = settings.apiKey;
          }
          return _buildForm();
        },
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _baseController,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            hintText: 'https://api.deepseek.com/v1',
            border: OutlineInputBorder(),
            helperText: 'OpenAI 兼容端点，末尾不要带 /chat/completions',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelController,
          decoration: const InputDecoration(
            labelText: '模型名',
            hintText: 'deepseek-v4-pro',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'API Key',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy || _testing ? null : _save,
                child: const Text('保存'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy || _testing ? null : _test,
                child: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('测试连接'),
              ),
            ),
          ],
        ),
        const Divider(height: 40),
        Text('备份', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportJson,
              icon: const Icon(Icons.data_object),
              label: const Text('导出 JSON'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportMarkdown,
              icon: const Icon(Icons.description_outlined),
              label: const Text('导出 Markdown'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importJson,
              icon: const Icon(Icons.upload_file),
              label: const Text('导入 JSON'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _clearAll,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('清空数据', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '说明：数据仅存本机；API Key 存于系统安全存储，导出备份时不会包含 Key。\n导入 JSON 会从剪贴板读取备份内容。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  AppSettings _current() => AppSettings(
        baseUrl: _baseController.text.trim(),
        model: _modelController.text.trim(),
        apiKey: _keyController.text.trim(),
      );

  Future<void> _save() async {
    await ref.read(settingsControllerProvider.notifier).save(_current());
    if (mounted) _snack('已保存');
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final result =
        await ref.read(settingsControllerProvider.notifier).testConnection(_current());
    if (mounted) {
      setState(() => _testing = false);
      _snack(result);
    }
  }

  Future<void> _exportJson() =>
      _export((svc) => svc.buildJson(), 'ai_reply_backup.json');
  Future<void> _exportMarkdown() =>
      _export((svc) => svc.buildMarkdown(), 'ai_reply_archive.md');

  Future<void> _export(
    Future<String> Function(BackupService) build,
    String filename,
  ) async {
    setState(() => _busy = true);
    try {
      final svc = BackupService(ref.read(databaseProvider));
      final content = await build(svc);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$filename');
      await file.writeAsString(content);
      await Share.shareXFiles([XFile(file.path)], subject: filename);
    } catch (e) {
      if (mounted) _snack('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importJson() async {
    setState(() => _busy = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.trim().isEmpty) {
        if (mounted) _snack('剪贴板为空，请先复制备份的 JSON 内容');
        return;
      }
      final svc = BackupService(ref.read(databaseProvider));
      await svc.importJson(text);
      if (mounted) _snack('导入成功');
    } catch (e) {
      if (mounted) _snack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空所有数据'),
        content: const Text('将删除全部对话与档案，且无法恢复。确定？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BackupService(ref.read(databaseProvider)).clearAll();
    if (mounted) _snack('已清空');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
