import 'package:flutter/widgets.dart';

/// When several pages share one sidebar item (Tasks and Referrals on the
/// desktop), the switch between them sits where the page title
/// would be, so every page keeps the same header line.
class PageTabsScope extends InheritedWidget {
  const PageTabsScope({super.key, required this.tabs, required super.child});

  final Widget tabs;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageTabsScope>()?.tabs;

  @override
  bool updateShouldNotify(PageTabsScope oldWidget) => oldWidget.tabs != tabs;
}

/// [title], or the page switch in its place.
Widget pageTitleOrTabs(BuildContext context, Widget title) =>
    PageTabsScope.of(context) ?? title;
