import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final String role;
  final String content;
  final bool streaming;
  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    this.streaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          content + (streaming ? ' ▌' : ''),
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
      ),
    );
  }
}
