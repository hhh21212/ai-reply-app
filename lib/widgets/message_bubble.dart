import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 一条消息气泡。AI 消息用 Markdown 渲染并可选中；用户消息用可选文本。
class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final bool streaming;
  final VoidCallback? onRegenerate;

  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.streaming = false,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final scheme = Theme.of(context).colorScheme;
    final text = content + (streaming ? ' ▌' : '');

    final Widget body = isUser
        ? SelectionArea(child: Text(text, style: const TextStyle(height: 1.5)))
        : MarkdownBody(
            data: text,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: const TextStyle(height: 1.5),
              code: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.84,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            if (!streaming)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionIcon(
                    icon: Icons.copy,
                    tooltip: '复制',
                    onTap: () => _copy(context),
                  ),
                  if (!isUser && onRegenerate != null)
                    _ActionIcon(
                      icon: Icons.refresh,
                      tooltip: '重新生成',
                      onTap: onRegenerate!,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制')));
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      color: Theme.of(context).colorScheme.outline,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
    );
  }
}
