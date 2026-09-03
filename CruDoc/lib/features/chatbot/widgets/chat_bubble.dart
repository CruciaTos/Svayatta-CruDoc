import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';

/// A single production-grade chat bubble for the CruDoc AI Assistant.
///
/// Features:
/// - WhatsApp & ChatGPT-style bubble geometry and aesthetics.
/// - Full Markdown rendering: headers (`###`), bullet points (`•`, `-`), numbered lists, bold text, inline code.
/// - Formatted timestamps (`10:45 AM`).
/// - Tap / long-press copy to clipboard action.
/// - Retry button for error states.
class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final VoidCallback? onRetry;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.onRetry,
  });

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text(
              'Message copied to clipboard',
              style: TextStyle(
                fontFamily: AppColors.bodyFontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = DateFormat('h:mm a').format(timestamp);

    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 36,
        bottom: 12,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            // Bot Avatar
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E78FF).withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _copyToClipboard(context),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  color: isUser ? null : (isError ? Colors.red.shade50 : Colors.white),
                  gradient: isUser
                      ? const LinearGradient(
                          colors: [Color(0xFF1E78FF), Color(0xFF0284C7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: isUser
                      ? null
                      : Border.all(
                          color: isError
                              ? Colors.red.shade200
                              : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isUser ? 20 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isUser
                          ? const Color(0xFF1E78FF).withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _buildFormattedContent(context),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formattedTime,
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontSize: 10,
                            color: isUser
                                ? Colors.white.withValues(alpha: 0.75)
                                : const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isUser) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.done_all_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ],
                        if (!isUser && !isError) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _copyToClipboard(context),
                            child: const Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isError && onRetry != null) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: onRetry,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Tap to retry query',
                              style: TextStyle(
                                fontFamily: AppColors.bodyFontFamily,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Parses markdown text blocks: headers, bullet lists, bold text, and numbered items.
  Widget _buildFormattedContent(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // 1. Headers: ### Header or ## Header or # Header
      if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: Text(
            trimmed.substring(4),
            style: TextStyle(
              fontFamily: AppColors.headingFontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isUser ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ));
      } else if (trimmed.startsWith('## ') || trimmed.startsWith('# ')) {
        final title = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: AppColors.headingFontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isUser ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ));
      }
      // 2. Bullet list items: • item or - item or * item
      else if (trimmed.startsWith('• ') ||
          trimmed.startsWith('- ') ||
          trimmed.startsWith('* ')) {
        final bulletText = trimmed.substring(2);
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• ',
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF1E78FF),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              Expanded(
                child: _buildInlineRichText(bulletText),
              ),
            ],
          ),
        ));
      }
      // 3. Numbered list items: 1. item
      else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        final match = RegExp(r'^(\d+\.)\s*(.*)').firstMatch(trimmed);
        final numPrefix = match?.group(1) ?? '1.';
        final content = match?.group(2) ?? trimmed;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$numPrefix ',
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: isUser ? Colors.white : const Color(0xFF1E78FF),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              Expanded(
                child: _buildInlineRichText(content),
              ),
            ],
          ),
        ));
      }
      // 4. Standard paragraph line
      else {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: _buildInlineRichText(trimmed),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Parses inline formatting: **bold** and `code`
  Widget _buildInlineRichText(String rawLine) {
    final baseStyle = TextStyle(
      fontFamily: AppColors.bodyFontFamily,
      color: isUser ? Colors.white : const Color(0xFF1E293B),
      fontSize: 14,
      height: 1.45,
    );

    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*|`(.*?)`');
    int lastEnd = 0;

    for (final match in regex.allMatches(rawLine)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: rawLine.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null) {
        // Bold
        spans.add(TextSpan(
          text: match.group(1),
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            color: isUser ? Colors.white : const Color(0xFF0F172A),
          ),
        ));
      } else if (match.group(2) != null) {
        // Inline code
        spans.add(TextSpan(
          text: ' ${match.group(2)} ',
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: isUser
                ? Colors.white.withValues(alpha: 0.2)
                : const Color(0xFFF1F5F9),
            color: isUser ? Colors.white : const Color(0xFF0284C7),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (spans.isEmpty) {
      return Text(rawLine, style: baseStyle);
    }

    if (lastEnd < rawLine.length) {
      spans.add(TextSpan(text: rawLine.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: spans,
      ),
    );
  }
}

/// Animated typing indicator shown while the bot is thinking.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 48, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Bot avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E78FF), Color(0xFF00C6FF)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (index) {
                        final delay = index * 0.2;
                        final t = (_controller.value - delay).clamp(0.0, 1.0);
                        final bounce = (1 - (2 * t - 1).abs()) * 4;
                        return Padding(
                          padding: EdgeInsets.only(right: index < 2 ? 4 : 0),
                          child: Transform.translate(
                            offset: Offset(0, -bounce),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E78FF)
                                    .withValues(alpha: 0.4 + t * 0.6),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
                const SizedBox(width: 8),
                const Text(
                  'CruDoc AI thinking...',
                  style: TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
