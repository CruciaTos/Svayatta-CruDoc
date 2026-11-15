import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Where the phone's island sits and how its shapes are sized, worked out
/// from the real top cutout (camera hole or Dynamic Island).
///
/// One gap [g] rules everything: the rest pill's distance from the top, the
/// grown shape's distance from the top and sides. The grown shape's top
/// corners are concentric with the display's corners, so that gap is the
/// same along the whole curve.
///
/// Pure: no BuildContext, so each phone model's numbers are easy to check.
class IslandGeometry {
  const IslandGeometry({
    required this.screen,
    required this.cornerRadius,
    required this.cameraRect,
    required this.wrapCamera,
    required this.g,
    required this.h,
    required this.restTop,
    required this.restCenterX,
    required this.cameraGap,
    required this.grownTop,
    required this.grownLeft,
    required this.grownWidth,
    required this.rTop,
    required this.rBot,
    required this.grownMinHeight,
    required this.useSuperellipse,
  });

  final Size screen;

  /// The display's corner radius, `R`.
  final double cornerRadius;

  /// The top cutout the rest pill wraps, in screen coordinates.
  final Rect? cameraRect;

  /// The rest pill sits over the cutout, with an empty middle for it.
  /// When false it sits fully below the status bar instead.
  final bool wrapCamera;

  /// The one gap, in logical pixels.
  final double g;

  /// Height of the rest pill, and of the band (the strip beside the camera
  /// where every grown state puts its header row).
  final double h;
  double get bandHeight => h;

  final double restTop;
  final double restCenterX;

  /// Width of the empty middle of the rest pill (and of a grown shape's
  /// band): the camera's width, or 0 without one.
  final double cameraGap;

  /// Grown shape: top, left and width. Centred on the screen.
  final double grownTop;
  final double grownLeft;
  final double grownWidth;

  /// Grown shape's corner radii: top is concentric with the display's.
  final double rTop;
  final double rBot;
  final double grownMinHeight;

  /// Continuous (squircle) corners, as on iOS; circular on Android.
  final bool useSuperellipse;

  /// Content padding inside grown shapes; clears the corner curve at band
  /// height.
  static const double contentPadding = 24;

  /// Taken off the concentric top radius (see [resolve]).
  static const double cornerTrim = 2;

  /// Space between a band half and the camera.
  static const double bandMargin = 8;

  /// The rest pill's smallest width: a bare pill just covering the camera.
  /// It grows past this only to fit what it shows.
  double get restWidth => cameraGap + h;

  /// The rest pill never grows past this, however long the name: its text
  /// ellipsizes instead.
  double get restMaxWidth => math.max(restWidth, grownWidth * 0.6);

  /// The rest pill's rect.
  Rect get restRect => Rect.fromCenter(
    center: Offset(restCenterX, restTop + h / 2),
    width: restWidth,
    height: h,
  );

  /// Width of each band half, measured from the shape's edge to
  /// [bandMargin] short of the camera gap. The label area inside a half is
  /// [bandHalf] - [contentPadding].
  double get bandHalf => (grownWidth - cameraGap) / 2 - bandMargin;

  static IslandGeometry resolve({
    required Size screen,
    required EdgeInsets viewPadding,
    required List<DisplayFeature> features,
    required TargetPlatform platform,
    required double cornerRadius,
  }) {
    final barTop = viewPadding.top;

    Rect? camera;
    for (final f in features) {
      if (f.type != DisplayFeatureType.cutout) continue;
      var b = f.bounds;
      // Top-edge cutouts only: anchored at the edge or floating inside the
      // status bar. Side and bottom cutouts don't affect the island.
      if (b.top >= barTop || b.bottom > barTop + 4) continue;
      // Android reports a punch hole as a strip from the screen edge down
      // to the hole's bottom. A round hole is as tall as it is wide, so
      // keep only that square at the strip's bottom.
      if (b.height > b.width * 1.3) {
        b = Rect.fromLTWH(b.left, b.bottom - b.width, b.width, b.width);
      }
      if (camera == null ||
          (b.center.dx - screen.width / 2).abs() <
              (camera.center.dx - screen.width / 2).abs()) {
        camera = b;
      }
    }
    // iOS reports no cutouts; the Dynamic Island's size is fixed.
    if (camera == null &&
        platform == TargetPlatform.iOS &&
        barTop >= 51 &&
        screen.width < screen.height) {
      camera = Rect.fromLTWH((screen.width - 126) / 2, 11, 126, 37);
    }

    final wrap =
        camera != null &&
        (camera.center.dx - screen.width / 2).abs() <= screen.width * 0.12 &&
        camera.width <= screen.width * 0.45;

    final c = camera;
    final g = wrap ? c!.top.clamp(6.0, 12.0) : 8.0;
    final h = wrap ? (2 * (c!.center.dy - g)).clamp(30.0, 40.0) : 34.0;
    // Without a camera to wrap, the pill (and every grown shape) sits
    // below the status bar rather than over it.
    final top = wrap ? g : barTop + 6;
    final cameraGap = wrap ? c!.width : 0.0;
    // Concentric with the display corner (outer = inner + gap), less a
    // small trim: the reported radius reads a touch large against the real
    // glass, so an exact match looks a pixel too round on the phone.
    final rTop = math.max(cornerRadius - g - cornerTrim, 12.0);
    final rBot = math.min(rTop, 28.0);

    return IslandGeometry(
      screen: screen,
      cornerRadius: cornerRadius,
      cameraRect: camera,
      wrapCamera: wrap,
      g: g,
      h: h,
      restTop: top,
      restCenterX: wrap ? c!.center.dx : screen.width / 2,
      cameraGap: cameraGap,
      grownTop: top,
      grownLeft: g,
      grownWidth: screen.width - 2 * g,
      rTop: rTop,
      rBot: rBot,
      grownMinHeight: math.max(h, rTop + rBot),
      useSuperellipse: platform == TargetPlatform.iOS,
    );
  }
}
