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
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: false),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (settings) => _buildBody(settings),
      ),
    );
  }

  Widget _buildBody(SettingsState settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('外观', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
            ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (s) => ref
              .read(settingsControllerProvider.notifier)
              .setThemeMode(s.first),
        ),
        const Divider(height: 40),
        Row(
          children: [
            Expanded(
              child: Text('API 配置',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => _editProfile(),
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (settings.profiles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('还没有配置，点右上角「新建」添加')),
          )
        else
          ...settings.profiles.map((p) => _profileCard(p, settings.active)),
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

  Widget _profileCard(ApiProfileModel p, ApiProfileModel? active) {
    final isActive = active?.id == p.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _editProfile(p),
        leading: Icon(
          isActive ? Icons.check_circle : Icons.circle_outlined,
          color: isActive ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Chip(
                  label: Text('当前'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${p.baseUrl}\n${p.model}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'active':
                ref
                    .read(settingsControllerProvider.notifier)
                    .setActive(p.id!);
                break;
              case 'test':
                _testProfile(p);
                break;
              case 'edit':
                _editProfile(p);
                break;
              case 'delete':
                _deleteProfile(p);
                break;
            }
          },
          itemBuilder: (_) => [
            if (!isActive)
              const PopupMenuItem(value: 'active', child: Text('设为当前')),
            const PopupMenuItem(value: 'test', child: Text('测试连接')),
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Future<void> _editProfile([ApiProfileModel? existing]) async {
    final profiles =
        ref.read(settingsControllerProvider).valueOrNull?.profiles ?? const [];
    final isFirst = profiles.isEmpty;
    final result = await showModalBottomSheet<ApiProfileModel>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProfileEditSheet(existing: existing, isFirst: isFirst),
    );
    if (result != null) {
      await ref.read(settingsControllerProvider.notifier).saveProfile(result);
      if (mounted) _snack(existing == null ? '已添加' : '已保存');
    }
  }

  Future<void> _deleteProfile(ApiProfileModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置'),
        content: Text('确定删除「${p.name}」？其 API Key 也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(settingsControllerProvider.notifier).deleteProfile(p.id!);
    if (mounted) _snack('已删除');
  }

  Future<void> _testProfile(ApiProfileModel p) async {
    setState(() => _busy = true);
    final result =
        await ref.read(settingsControllerProvider.notifier).testConnection(p);
    if (mounted) {
      setState(() => _busy = false);
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

class _ProfileEditSheet extends StatefulWidget {
  final ApiProfileModel? existing;
  final bool isFirst;

  const _ProfileEditSheet({this.existing, required this.isFirst});

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _base = TextEditingController(
      text: widget.existing?.baseUrl ?? SettingsService.defaultBaseUrl);
  late final TextEditingController _model = TextEditingController(
      text: widget.existing?.model ?? SettingsService.defaultModel);
  late final TextEditingController _key =
      TextEditingController(text: widget.existing?.apiKey ?? '');
  late bool _active = widget.existing?.active ?? widget.isFirst;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? '新建 API 配置' : '编辑 API 配置',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：DeepSeek',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _base,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.deepseek.com/v1',
                border: OutlineInputBorder(),
                helperText: 'OpenAI 兼容端点，末尾不要带 /chat/completions',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: '模型名',
                hintText: 'deepseek-v4-pro',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
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
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('设为当前配置'),
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final existing = widget.existing;
    Navigator.pop(
      context,
      ApiProfileModel(
        id: existing?.id,
        name: _name.text,
        baseUrl: _base.text,
        model: _model.text,
        apiKey: _key.text,
        active: _active,
        sortOrder: existing?.sortOrder ?? 0,
      ),
    );
  }
}
