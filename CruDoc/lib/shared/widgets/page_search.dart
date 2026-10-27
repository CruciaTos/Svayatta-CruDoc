import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The search box of the page on screen, so Ctrl F (⌘F on a Mac) reaches
/// it from anywhere on the desktop. Page search boxes add their focus node
/// while they are on screen; the newest one on the top route wins (a page
/// pushed over a list hides the list's box). Boxes inside dialogs stay out.
abstract final class PageSearch {
  static final List<FocusNode> _boxes = [];

  static void add(FocusNode box) => _boxes
    ..remove(box)
    ..add(box);

  static void remove(FocusNode box) => _boxes.remove(box);

  static FocusNode? get _target {
    for (final box in _boxes.reversed) {
      final context = box.context;
      if (context == null || !context.mounted) continue;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) continue;
      return box;
    }
    return null;
  }

  /// Whether the page on screen has a search box.
  static bool get available => _target != null;

  /// Focuses the page's search box; false when the page has none.
  static bool focus() {
    final box = _target;
    if (box == null) return false;
    box.requestFocus();
    return true;
  }

  /// The keycap on page search boxes.
  static String get shortcut =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘F' : 'Ctrl F';
}
