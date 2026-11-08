import 'dart:async';

import 'package:flutter/material.dart';

/// One short message for the top island (what a SnackBar used to show),
/// with an optional action such as Undo.
class AppNotice {
  AppNotice({
    required this.text,
    this.actionLabel,
    this.onAction,
    this.from,
    this.to,
    this.duration = const Duration(seconds: 4),
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// For a change (a visit moved): what it was and what it is now.
  final String? from;
  final String? to;
  final Duration duration;
}

/// The message the island is showing now, if any. The island (the voice
/// strip on desktop, the status-bar island on phones) listens and grows to
/// show it.
abstract final class AppNotices {
  static final current = ValueNotifier<AppNotice?>(null);

  /// An island is on screen to show notices. When none is (e.g. the
  /// sign-in screen) messages fall back to a normal SnackBar.
  static bool hosted = false;

  static Timer? _timer;

  static void show(AppNotice n) {
    _timer?.cancel();
    current.value = n;
    _timer = Timer(n.duration, clear);
  }

  static void clear() {
    _timer?.cancel();
    current.value = null;
  }
}

extension IslandSnackBar on ScaffoldMessengerState {
  /// Same call as [showSnackBar], but the message appears in the island.
  /// A SnackBar whose content isn't plain text, or no island on screen,
  /// shows as a normal SnackBar.
  void showIsland(SnackBar bar, {String? from, String? to}) {
    final content = bar.content;
    final text = content is Text
        ? (content.data ?? content.textSpan?.toPlainText())
        : null;
    if (text == null || !AppNotices.hosted) {
      showSnackBar(bar);
      return;
    }
    final action = bar.action;
    AppNotices.show(
      AppNotice(
        text: text,
        actionLabel: action?.label,
        onAction: action?.onPressed,
        from: from,
        to: to,
        duration: bar.duration,
      ),
    );
  }
}
