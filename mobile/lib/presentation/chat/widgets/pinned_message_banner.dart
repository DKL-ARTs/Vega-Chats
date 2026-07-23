import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class PinnedMessageBanner extends StatelessWidget {
  final List<Map<String, dynamic>> pinnedMessages;
  final int currentIndex;
  final VoidCallback onTap;
  final VoidCallback onUnpinCurrent;

  const PinnedMessageBanner({
    super.key,
    required this.pinnedMessages,
    required this.currentIndex,
    required this.onTap,
    required this.onUnpinCurrent,
  });

  @override
  Widget build(BuildContext context) {
    if (pinnedMessages.isEmpty) return const SizedBox.shrink();

    final safeIndex = currentIndex.clamp(0, pinnedMessages.length - 1);
    final msg = pinnedMessages[safeIndex];
    final content = (msg['content'] as String? ?? '').replaceAll(RegExp(r'!\[.*?\]\(.*?\)', dotAll: true), '').trim();
    final role = msg['role'] as String? ?? 'user';
    final senderName = role == 'user' ? 'Вы' : 'Vega AI';

    final total = pinnedMessages.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1B192A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.35), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // Accent Bar & Pin Icon
                Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    color: VegaTheme.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.push_pin_rounded,
                  color: VegaTheme.accent,
                  size: 16,
                ),
                const SizedBox(width: 8),

                // Message snippet & Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        total > 1 ? 'Закреплённое сообщение #${safeIndex + 1} из $total' : 'Закреплённое сообщение',
                        style: const TextStyle(
                          color: VegaTheme.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$senderName: ${content.isNotEmpty ? content : 'Изображение / файл'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VegaTheme.textPrimary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Unpin / Close button
                InkWell(
                  onTap: onUnpinCurrent,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      color: VegaTheme.textSecondary,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
