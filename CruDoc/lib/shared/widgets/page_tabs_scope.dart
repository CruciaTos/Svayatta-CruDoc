import 'package:flutter/widgets.dart';

/// When several pages share one sidebar item (Tasks and Referrals on the
/// desktop), the switch between them sits where the page title
/// would be, so every page keeps the same header line.
class PageTabsScope extends InheritedWidget {
  const PageTabsScope({
    super.key,
    required this.tabs,
    this.title,
    required super.child,
  });

  final Widget? tabs;
  final String? title;

  static Widget? of(BuildContext context) => tabsOf(context);

  static Widget? tabsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageTabsScope>()?.tabs;

  static String? titleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageTabsScope>()?.title;

  @override
  bool updateShouldNotify(PageTabsScope oldWidget) =>
      oldWidget.tabs != tabs || oldWidget.title != title;
}

/// A page opened from another page (Recalls from Patients, Procedures
/// from Settings): its header puts a back button before the title,
/// "Back to [label]".
class PageBackScope extends InheritedWidget {
  const PageBackScope({
    super.key,
    required this.label,
    required this.onBack,
    required super.child,
  });

  final String label;
  final VoidCallback onBack;

  static PageBackScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageBackScope>();

  @override
  bool updateShouldNotify(PageBackScope oldWidget) =>
      oldWidget.label != label || oldWidget.onBack != onBack;
}

/// [title], or the page switch in its place.
Widget pageTitleOrTabs(BuildContext context, Widget title) =>
    PageTabsScope.of(context) ?? title;
