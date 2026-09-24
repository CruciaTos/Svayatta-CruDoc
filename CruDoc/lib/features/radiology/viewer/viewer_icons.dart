import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Stroke icons for the 2D viewer's tools (24-unit viewBox, Calm Clinical
/// style).
abstract final class RadViewerIcons {
  static const select = CruIconData('M5.5 3.5v14l4-3.5 2.8 6 2.6-1.2-2.8-5.9h5.4z');

  static const pan = CruIconData(
    'M12 3v18M3 12h18M9.5 5.5 12 3l2.5 2.5M9.5 18.5 12 21l2.5-2.5'
    'M5.5 9.5 3 12l2.5 2.5M18.5 9.5 21 12l-2.5 2.5',
  );

  static const zoom = CruIconData(
    'M20 20l-4.8-4.8M10.5 8v5M8 10.5h5',
    circles: [(10.5, 10.5, 6.5)],
  );

  /// Brightness / contrast: a half-hatched circle.
  static const window = CruIconData(
    'M12 3.5v17M12 7h6.4M12 11h8M12 15h7.5M12 18.5h5',
    circles: [(12, 12, 8.5)],
  );

  static const length = CruIconData('M5 19 19 5M3 17l4 4M17 3l4 4');

  static const angle = CruIconData('M4 19.5h16M4 19.5 15 5M9.5 19.5A5.5 5.5 0 0 0 7.3 15.1');

  static const polygon = CruIconData('M5 8l6-4.5 8 4-1.5 9.5-9.5 2.5z');

  static const ellipse = CruIconData('M3.5 12a8.5 6 0 1 0 17 0 8.5 6 0 1 0-17 0z');

  static const rect = CruIconData('', rects: [(4, 6, 16, 12, 1.5)]);

  static const polyline = CruIconData('M3.5 17.5l5-8 5 5 7-9');

  static const arrow = CruIconData('M19 19 6 6M6 6v7M6 6h7');

  static const text = CruIconData('M5 6.5V5h14v1.5M12 5v14M9.5 19h5');

  static const pen = CruIcons.pen;

  static const tooth = CruIconData(
    'M7.5 4C5 4 4 6 4 8.5c0 2.5 1 4 1.5 6.5.4 2.2.9 5 2.5 5 1.8 0 1.8-5 4-5s2.2 5 4 5'
    'c1.6 0 2.1-2.8 2.5-5 .5-2.5 1.5-4 1.5-6.5C20 6 19 4 16.5 4c-1.8 0-2.7 1-4.5 1S9.3 4 7.5 4z',
  );

  /// Calibrate: a ruler.
  static const calibrate = CruIconData(
    'M7 8.5v3M11 8.5v2M15 8.5v3',
    rects: [(3, 8.5, 18, 7, 1.5)],
  );

  /// Magnifier loupe.
  static const loupe = CruIconData(
    'M20 20l-4.8-4.8',
    circles: [(10.5, 10.5, 6.5), (10.5, 10.5, 2.2)],
  );

  static const fit = CruIconData('M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5');

  static const rotate = CruIconData('M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4.5v4h-4');

  static const flipH = CruIconData('M12 3.5v17M9 6.5 4 17.5h5zM15 6.5l5 11h-5z');

  static const flipV = CruIconData('M3.5 12h17M6.5 9 17.5 4v5zM6.5 15l11 5v-5z');

  static const invert = CruIconData(
    'M12 3.5v17M15 8.5v7M18 10v4',
    circles: [(12, 12, 8.5)],
  );

  static const reset = CruIconData('M4.5 12a7.5 7.5 0 1 0 2.2-5.3M4.5 4.5v4h4');

  static const layout1x1 = CruIconData('', rects: [(4, 4, 16, 16, 2)]);
  static const layout1x2 =
      CruIconData('', rects: [(3.5, 4, 7.5, 16, 1.5), (13, 4, 7.5, 16, 1.5)]);
  static const layout2x1 =
      CruIconData('', rects: [(4, 3.5, 16, 7.5, 1.5), (4, 13, 16, 7.5, 1.5)]);
  static const layout2x2 = CruIconData('', rects: [
    (3.5, 3.5, 7.5, 7.5, 1.5),
    (13, 3.5, 7.5, 7.5, 1.5),
    (3.5, 13, 7.5, 7.5, 1.5),
    (13, 13, 7.5, 7.5, 1.5),
  ]);
  static const layout1p3 = CruIconData('', rects: [
    (3.5, 4, 10, 16, 1.5),
    (15.5, 4, 5, 4.5, 1),
    (15.5, 9.75, 5, 4.5, 1),
    (15.5, 15.5, 5, 4.5, 1),
  ]);

  static const link = CruIconData(
    'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1'
    'M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
  );

  /// Compare with an earlier study: a split view.
  static const compare = CruIconData('M12 4v16', rects: [(3.5, 5, 17, 14, 2)]);

  /// Key image: a bookmark.
  static const keyImage = CruIconData('M7 4h10v16l-5-3.5L7 20z');

  static const undo = CruIconData('M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11');
  static const redo = CruIconData('M15 14l5-5-5-5M20 9H9.5a5.5 5.5 0 0 0 0 11H13');

  /// Cephalometric tracing: a profile.
  static const ceph = CruIconData(
    'M14.5 3.5C10 3.5 6.5 6.5 6.5 11L4.5 14l2 .8V18a2 2 0 0 0 2 2H11v1.5'
    'M14.5 3.5c3.3 0 5.5 2.7 5.5 6 0 3.5-2.5 5-2.5 8v4',
  );

  /// Compare / subtract: two overlapping squares.
  static const subtract =
      CruIconData('', rects: [(3.5, 3.5, 11, 11, 2), (9.5, 9.5, 11, 11, 2)]);

  /// Reading mode: arrows to the corners.
  static const readingMode = CruIconData(
    'M4 9V4h5M4 4l5.5 5.5M20 9V4h-5M20 4l-5.5 5.5M4 15v5h5M4 20l5.5-5.5'
    'M20 15v5h-5M20 20l-5.5-5.5',
  );

  static const thumbnails = CruIcons.sidebar;

  static const panel = CruIconData('M14.5 4.5v15', rects: [(3.5, 4.5, 17, 15, 3.5)]);

  static const keyboard = CruIconData(
    'M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M7.5 14h9',
    rects: [(2.5, 6, 19, 12, 2)],
  );

  static const export = CruIcons.download;

  static const file = CruIconData(
    'M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8zM14 3.5V8h4.5',
  );

  static const frames = CruIconData('M8 4h11a1 1 0 0 1 1 1v11', rects: [(4, 7.5, 12.5, 12.5, 1.5)]);

  static const info = CruIconData('M12 11v5.5M12 7.5h.01', circles: [(12, 12, 8.5)]);

  static const sliders = CruIcons.settings;
}
