import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/viewer_plus/image_filters.dart';

/// How the doctor left one image (or one slice stack): window, invert,
/// rotation, flips and filters. Saved with the study so the image opens
/// the same way next time, on any device. Zoom and pan are only looking
/// around, so they aren't kept.
@immutable
class RadImageLook {
  const RadImageLook({
    required this.center,
    required this.width,
    this.invert = false,
    this.quarterTurns = 0,
    this.flipH = false,
    this.flipV = false,
    this.filters = const RadFilterSettings(),
    this.lastSlice,
  });

  /// Study `extras` key: image (or stack) key → look.
  static const extrasKey = 'views';

  final double center;
  final double width;

  /// Inverted against how the image opens (not the photometric default).
  final bool invert;
  final int quarterTurns;
  final bool flipH;
  final bool flipV;
  final RadFilterSettings filters;

  /// The slice (image id) of a stack the doctor was last looking at, so the
  /// stack reopens there.
  final String? lastSlice;

  RadImageLook copyWith({
    double? center,
    double? width,
    bool? invert,
    int? quarterTurns,
    bool? flipH,
    bool? flipV,
    RadFilterSettings? filters,
    String? lastSlice,
  }) => RadImageLook(
    center: center ?? this.center,
    width: width ?? this.width,
    invert: invert ?? this.invert,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
    filters: filters ?? this.filters,
    lastSlice: lastSlice ?? this.lastSlice,
  );

  Map<String, dynamic> toJson() => {
    'center': center,
    'width': width,
    if (invert) 'invert': true,
    if (quarterTurns != 0) 'turns': quarterTurns,
    if (flipH) 'flipH': true,
    if (flipV) 'flipV': true,
    'filters': filters.toJson(),
    if (lastSlice != null) 'lastSlice': lastSlice,
  };

  static RadImageLook? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = Map<String, dynamic>.from(j);
    final c = m['center'], w = m['width'];
    if (c is! num || w is! num) return null;
    final f = m['filters'];
    return RadImageLook(
      center: c.toDouble(),
      width: w.toDouble(),
      invert: m['invert'] == true,
      quarterTurns: ((m['turns'] as num?)?.toInt() ?? 0) % 4,
      flipH: m['flipH'] == true,
      flipV: m['flipV'] == true,
      filters: f is Map
          ? RadFilterSettings.fromJson(Map<String, dynamic>.from(f))
          : const RadFilterSettings(),
      lastSlice: m['lastSlice'] is String ? m['lastSlice'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RadImageLook &&
      other.center == center &&
      other.width == width &&
      other.invert == invert &&
      other.quarterTurns == quarterTurns &&
      other.flipH == flipH &&
      other.flipV == flipV &&
      mapEquals(other.filters.toJson(), filters.toJson());

  @override
  int get hashCode =>
      Object.hash(center, width, invert, quarterTurns, flipH, flipV);
}

/// The looks saved on [s], by image (or stack) key.
Map<String, RadImageLook> radLooksOf(RadStudy s) {
  final all = s.extras[RadImageLook.extrasKey];
  if (all is! Map) return const {};
  return {
    for (final e in all.entries)
      e.key.toString(): ?RadImageLook.fromJson(e.value),
  };
}

/// [extras] with [changes] applied: a look is stored, null removes the
/// image's entry (it is back to how it opens).
Map<String, dynamic> radExtrasWithLooks(
  Map<String, dynamic> extras,
  Map<String, RadImageLook?> changes,
) {
  if (changes.isEmpty) return extras;
  final old = extras[RadImageLook.extrasKey];
  final views = <String, dynamic>{
    if (old is Map) ...Map<String, dynamic>.from(old),
  };
  for (final e in changes.entries) {
    final look = e.value;
    if (look == null) {
      views.remove(e.key);
    } else {
      views[e.key] = look.toJson();
    }
  }
  return {...extras, RadImageLook.extrasKey: views};
}
