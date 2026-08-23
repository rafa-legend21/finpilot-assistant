import 'package:flutter/material.dart';

class ClarificationBubble extends StatelessWidget {
  const ClarificationBubble({
    required this.text,
    required this.isUser,
    this.subtitle,
    super.key,
  });

  final String text;
  final bool isUser;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.amber.shade50,
            border: Border.all(
              color: isUser
                  ? Theme.of(context).colorScheme.primary
                  : Colors.amber.shade700,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      );
}
