import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class MobileNavItem {
  const MobileNavItem(this.label, this.icon);
  final String label;
  final CruIconData icon;
}

/// The phone's floating tab bar: the Up next card's ink-blue gradient
/// with an embossed rim (light along the top, grey along the bottom, like
/// iPhone hardware), five tabs, and a see-through shade with a white
/// border on the current one.
///
/// The lens follows the pages as they are swiped, and the bar itself can
/// be dragged: the lens (and the pages behind it) follow the thumb, snap
/// onto a tab when close to it (with a tick), stay put when held between
/// two, and settle on the nearest tab on release.
class MobileNavBar extends StatefulWidget {
  const MobileNavBar({
    super.key,
    required this.controller,
    required this.items,
    this.badges = const {},
  });

  final PageController controller;
  final List<MobileNavItem> items;

  /// Small amber counts on tabs (people waiting on Schedule).
  final Map<int, int> badges;

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    // Penn Blue into Neon Blue, the reference palette's two blues.
    colors: [Color(0xFF16246A), Color(0xFF3355E8)],
  );

  @override
  State<MobileNavBar> createState() => _MobileNavBarState();
}

class _MobileNavBarState extends State<MobileNavBar> {
  bool _dragging = false;
  int _lastTick = -1;

  /// Width of the embossed rim around the bar.
  static const double _rim = 1.5;

  int get _count => widget.items.length;

  /// The newest page view on the controller. While the tab pager is
  /// rebuilt, two can be attached for a frame; reading `position` then
  /// would assert.
  ScrollPosition? get _position {
    final c = widget.controller;
    return c.hasClients ? c.positions.last : null;
  }

  double get _page {
    final initial = widget.controller.initialPage.toDouble();
    final p = _position;
    if (p == null || !p.hasContentDimensions || p is! PageMetrics) {
      return initial;
    }
    return (p as PageMetrics).page ?? initial;
  }

  void _goTo(int index) {
    MobileHaptics.select();
    widget.controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  /// Within this distance of a tab (in tabs) the lens is pulled onto it.
  static const double _magnet = 0.16;

  /// Moves the pages with the thumb: position is in tabs. Near a tab the
  /// lens snaps onto it (with a tick); held between two tabs it stays
  /// between them. Nothing settles until the thumb lets go.
  void _dragTo(double localX, double slot) {
    final pos = _position;
    if (pos == null) return;
    final raw = ((localX - slot / 2) / slot).clamp(0.0, _count - 1.0);
    final near = raw.round();
    final d = raw - near;
    final double p;
    if (d.abs() <= _magnet) {
      p = near.toDouble();
      if (near != _lastTick) {
        _lastTick = near;
        MobileHaptics.select();
      }
    } else {
      // Continuous outside the magnet: half a tab away is still halfway.
      p = near + d.sign * (d.abs() - _magnet) / (0.5 - _magnet) * 0.5;
      _lastTick = -1;
    }
    pos.jumpTo(p * pos.viewportDimension);
  }

  void _settle() {
    setState(() => _dragging = false);
    _lastTick = -1;
    widget.controller.animateToPage(
      _page.round(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = (constraints.maxWidth - _rim * 2) / _count;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) =>
              _goTo((d.localPosition.dx / slot).floor().clamp(0, _count - 1)),
          onHorizontalDragStart: (d) {
            setState(() => _dragging = true);
            _lastTick = _page.round();
            _dragTo(d.localPosition.dx, slot);
          },
          onHorizontalDragUpdate: (d) => _dragTo(d.localPosition.dx, slot),
          onHorizontalDragEnd: (_) => _settle(),
          onHorizontalDragCancel: _settle,
          // The rim: a white-to-grey ring around the blue bar.
          child: Container(
            height: MobileMetrics.navHeight,
            padding: const EdgeInsets.all(_rim),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFE2E7EF),
                  Color(0xFFA9B3C2),
                ],
                stops: [0, 0.5, 1],
              ),
              shadows: [
                BoxShadow(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: DecoratedBox(
              decoration: const ShapeDecoration(
                shape: StadiumBorder(),
                gradient: MobileNavBar._gradient,
              ),
              // Pressed-in edges: a highlight inside the top, a shade
              // inside the bottom.
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.22, 0.7, 1],
                    colors: [
                      Colors.white.withValues(alpha: 0.26),
                      Colors.white.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.16),
                    ],
                  ),
                ),
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final page = _page;
                    final inner = MobileMetrics.navHeight - _rim * 2;
                    return Stack(
                      children: [
                        Positioned(
                          left: page * slot + 4,
                          top: 4,
                          width: slot - 8,
                          height: inner - 8,
                          child: AnimatedScale(
                            scale: _dragging ? 1.08 : 1,
                            duration: CruMotion.fast,
                            curve: CruMotion.curve,
                            child: _Lens(lifted: _dragging),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _count; i++)
                              SizedBox(
                                width: slot,
                                child: _Item(
                                  item: widget.items[i],
                                  // 1 on the tab, 0 one tab away or more.
                                  focus: (1 - (page - i).abs()).clamp(0.0, 1.0),
                                  badge: widget.badges[i] ?? 0,
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The current tab's shade: see-through white with a crisp white border.
class _Lens extends StatelessWidget {
  const _Lens({required this.lifted});

  final bool lifted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: CruMotion.fast,
      curve: CruMotion.curve,
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: lifted ? 0.94 : 1),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.focus, required this.badge});

  final MobileNavItem item;
  final double focus;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(
      Colors.white.withValues(alpha: 0.78),
      const Color(0xFF2B4BDB),
      Curves.easeOut.transform(focus),
    )!;
    return Semantics(
      button: true,
      selected: focus > 0.5,
      label: item.label,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CruIcon(
              item.icon,
              size: 24,
              strokeWidth: 1.6 + 0.4 * focus,
              color: color,
            ),
            if (badge > 0)
              Positioned(
                right: -9,
                top: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: const Color(0xFFFF9F0A),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: const Color(0xFF2B4BDB),
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: MobileType.micro.w700.tabular.copyWith(
                      fontSize: 10.5,
                      height: 1,
                      color: const Color(0xFF3B2300),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
