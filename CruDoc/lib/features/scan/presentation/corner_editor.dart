import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/scan/data/docscan/corner_set.dart';
import 'package:doctor_management_app/features/scan/data/docscan/detector.dart';
import 'package:doctor_management_app/features/scan/data/docscan/geometry.dart';
import 'package:doctor_management_app/features/scan/data/docscan/page_render.dart';

/// Where a picture of [picture] size sits on a screen of [view] size: filling
/// it like the live camera (`settled` 0), or whole and clear of the controls
/// so every corner can be reached (`settled` 1).
Rect pictureRect(Size picture, Size view, EdgeInsets safe, double settled) {
  Rect fit(Rect area, double scale) => Rect.fromCenter(
    center: area.center,
    width: picture.width * scale,
    height: picture.height * scale,
  );
  final screen = Offset.zero & view;
  final cover = fit(
    screen,
    math.max(view.width / picture.width, view.height / picture.height),
  );
  if (settled <= 0) return cover;
  // Below the guidance pill, above the two buttons.
  final area = Rect.fromLTRB(
    28,
    safe.top + 72,
    view.width - 28,
    view.height - safe.bottom - 112,
  );
  final contain = fit(
    area,
    math.min(area.width / picture.width, area.height / picture.height),
  );
  return Rect.lerp(cover, contain, settled.clamp(0.0, 1.0))!;
}

/// The corners of an already kept page while they are moved by finger.
/// Everything is in the picture's own pixels; the screen maps to it through
/// [pictureRect]. (On the live camera the corners are followed instead: see
/// `CornerTracker`.)
class CornerEditor extends ChangeNotifier {
  CornerEditor({
    required this.source,
    required this.picture,
    required this.image,
    required this.corners,
    required this.replaces,
  });

  final PageSource source;
  final EditablePicture picture;
  final ui.Image image;
  CornerSet corners;

  /// The kept page these corners will replace.
  final int replaces;

  /// The picture's size in pixels.
  Size get size =>
      Size(picture.frame.width.toDouble(), picture.frame.height.toDouble());

  /// The corner under the finger, and where the finger is on screen.
  int? active;
  Offset? finger;

  /// Corners that settled onto a corner sensed in the picture.
  final Set<int> found = {};

  Pt _dragFrom = const Pt(0, 0);

  /// The corner sensed near the finger during a drag, and when it was last
  /// looked for.
  Pt? _magnet;
  final Stopwatch _sinceLook = Stopwatch();

  /// Takes hold of corner [i] to drag it.
  void grab(int i, Offset at) {
    active = i;
    finger = at;
    _dragFrom = corners.points[i];
    _magnet = null;
    _sinceLook.stop();
    notifyListeners();
  }

  /// The held corner follows the finger, which has travelled [by] pixels of
  /// the picture since it took hold. Following the travel, not the finger
  /// itself, keeps the corner from jumping under it. A corner sensed within
  /// [pull] of there draws it on. True as it catches.
  bool drag(Offset at, Offset by, double pull) {
    final i = active;
    if (i == null) return false;
    finger = at;
    final to = _inside(Pt(_dragFrom.x + by.dx, _dragFrom.y + by.dy));
    // Looking costs a few milliseconds: not on every movement.
    if (!_sinceLook.isRunning || _sinceLook.elapsedMilliseconds >= 50) {
      _magnet = _sense(i, to, pull);
      _sinceLook
        ..reset()
        ..start();
    }
    final magnet = _magnet;
    final caught = magnet != null && magnet.distanceTo(to) <= 1.3 * pull;
    final was = found.contains(i);
    caught ? found.add(i) : found.remove(i);
    corners = corners.move(i, caught ? magnet : to);
    notifyListeners();
    return caught && !was;
  }

  /// A long press at [point]: the corner sensed there becomes one of the
  /// four, or the spot itself when nothing is sensed within [reach]. True
  /// when a corner was sensed.
  bool press(Offset at, Pt point, double reach) {
    // A corner already held is the one meant; otherwise the best placed.
    final held = active;
    final spot = _inside(point);
    // Well inside a page, away from its corners: that whole page is meant.
    if (held == null) {
      final page = PageRender.pageAt(picture.frame, spot);
      if (page != null &&
          page.corners.every((c) => c.distanceTo(spot) > 1.5 * reach)) {
        corners = CornerSet(page.corners, const [true, true, true, true]);
        found.addAll(const [0, 1, 2, 3]);
        active = null;
        finger = null;
        notifyListeners();
        return true;
      }
    }
    final (next, i) = held == null
        ? corners.place(spot)
        : (corners.move(held, spot), held);
    corners = next;
    active = i;
    finger = at;
    found.remove(i);
    final sensed = _snap(i, reach);
    _dragFrom = corners.points[i];
    notifyListeners();
    return sensed;
  }

  /// The finger lifted. A corner left right beside a real one ([reach] > 0)
  /// settles onto it. True when it did.
  bool release({double reach = 0}) {
    final i = active;
    final sensed = i != null && reach > 0 && _snap(i, reach);
    active = null;
    finger = null;
    corners = corners.untangled();
    notifyListeners();
    return sensed;
  }

  bool _snap(int i, double reach) {
    final corner = _sense(i, corners.points[i], reach);
    if (corner == null) return false;
    corners = corners.move(i, corner);
    found.add(i);
    return true;
  }

  /// A corner of the page near [at] that corner [i] could be.
  Pt? _sense(int i, Pt at, double reach) {
    final corner = DocumentDetector.cornerNear(
      picture.frame,
      at,
      radius: reach,
      inward: at + Quad.inward[i] * (4 * reach),
    );
    if (corner == null) return null;
    // Two corners never share a spot.
    for (var k = 0; k < 4; k++) {
      if (k != i && corners.points[k].distanceTo(corner) < reach / 2) {
        return null;
      }
    }
    return corner;
  }

  Pt _inside(Pt p) =>
      Pt(p.x.clamp(0.0, size.width), p.y.clamp(0.0, size.height));

  /// The screen picture for [source].
  static Future<ui.Image> decode(EditablePicture picture) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      picture.rgba,
      picture.width,
      picture.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  @override
  void dispose() {
    image.dispose();
    super.dispose();
  }
}

/// The kept picture, the outline over it and the four handles.
class CornerPainter extends CustomPainter {
  CornerPainter({
    required this.editor,
    required this.rect,
    required this.settled,
    required this.accent,
    required this.warning,
    required this.sensed,
  });

  final CornerEditor editor;
  final Rect rect;

  /// 0 over the live view, 1 on its own black screen.
  final double settled;
  final Color accent;
  final Color warning;
  final Color sensed;

  @override
  void paint(Canvas canvas, Size size) {
    if (settled > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: settled),
      );
    }
    final image = editor.image;
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final scale = rect.width / editor.size.width;
    final points = [
      for (final p in editor.corners.points)
        rect.topLeft + Offset(p.x, p.y) * scale,
    ];
    final color = editor.corners.valid ? accent : warning;
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < 4; i++) {
      // The held corner shows in the magnifier; keep the spot itself clear.
      final held = i == editor.active;
      final radius = held ? 18.0 : 12.0;
      final fill = editor.found.contains(i) ? sensed : Colors.white;
      canvas.drawCircle(
        points[i],
        radius,
        Paint()..color = fill.withValues(alpha: held ? 0.25 : 0.9),
      );
      canvas.drawCircle(
        points[i],
        radius,
        Paint()
          ..color = held ? fill : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(CornerPainter old) => true;
}

/// A magnified view of the corner being placed, kept clear of the finger.
/// It enlarges whatever is behind it, so it works over the running camera
/// and over a kept picture alike.
class CornerLoupe extends StatelessWidget {
  const CornerLoupe({
    super.key,
    required this.finger,
    required this.corner,
    required this.view,
    required this.safeTop,
    required this.ring,
  });

  static const radius = 62.0;
  static const _zoom = 2.5;

  /// Where the finger and the corner are on screen.
  final Offset finger;
  final Offset corner;
  final Size view;
  final double safeTop;
  final Color ring;

  /// Above the finger; near the top of the screen, in the far top corner.
  static Offset centreFor(Offset finger, Size view, double safeTop) {
    final above = finger.translate(0, -(radius + 56));
    // Below the close button and the guidance pill.
    final top = safeTop + 104;
    if (above.dy - radius >= top) {
      return Offset(
        above.dx.clamp(radius + 8, view.width - radius - 8),
        above.dy,
      );
    }
    return Offset(
      finger.dx < view.width / 2 ? view.width - radius - 16 : radius + 16,
      top + radius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final centre = centreFor(finger, view, safeTop);
    return Stack(
      children: [
        Positioned(
          left: centre.dx - radius,
          top: centre.dy - radius,
          child: RawMagnifier(
            size: const Size.square(2 * radius),
            magnificationScale: _zoom,
            focalPointOffset: corner - centre,
            clipBehavior: Clip.antiAlias,
            decoration: MagnifierDecoration(
              shape: CircleBorder(side: BorderSide(color: ring, width: 3)),
            ),
            child: const CustomPaint(painter: _CrossPainter()),
          ),
        ),
      ],
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
    canvas.drawLine(c.translate(-9, 0), c.translate(9, 0), paint);
    canvas.drawLine(c.translate(0, -9), c.translate(0, 9), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => false;
}
