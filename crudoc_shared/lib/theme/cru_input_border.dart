import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:crudoc_shared/theme/cru_tokens.dart';

/// The ring around a themed text field: a rounded superellipse at
/// [CruRadius.control], the same shape as `cruShape`.
///
/// Unlike [OutlineInputBorder] it reports `isOutline == false`, so a
/// floating label sits inside the inset fill instead of notching the
/// (usually transparent) ring.
@immutable
class CruInputBorder extends InputBorder {
  const CruInputBorder({
    super.borderSide = BorderSide.none,
    this.radius = CruRadius.control,
  });

  final double radius;

  RoundedSuperellipseBorder get _shape => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
    side: borderSide,
  );

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  CruInputBorder copyWith({BorderSide? borderSide}) =>
      CruInputBorder(borderSide: borderSide ?? this.borderSide, radius: radius);

  @override
  CruInputBorder scale(double t) =>
      CruInputBorder(borderSide: borderSide.scale(t), radius: radius * t);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is CruInputBorder) {
      return CruInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        radius: lerpDouble(a.radius, radius, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is CruInputBorder) {
      return CruInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        radius: lerpDouble(radius, b.radius, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) => _shape.paint(canvas, rect, textDirection: textDirection);

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CruInputBorder &&
      other.borderSide == borderSide &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(runtimeType, borderSide, radius);
}

/// A [CruInputBorder] whose ring follows the field: [error] when it has
/// a validation error, [focused] while focused, [rest] otherwise.
///
/// Used as the theme's `border` (not `enabledBorder`/`focusedBorder`) so
/// a field that passes its own `border`, such as [InputBorder.none] or
/// [InputDecoration.collapsed], keeps it.
@immutable
class CruStateInputBorder extends CruInputBorder
    implements WidgetStateInputBorder {
  const CruStateInputBorder({
    required this.rest,
    required this.focused,
    required this.error,
    super.radius,
  }) : super(borderSide: rest);

  final BorderSide rest;
  final BorderSide focused;
  final BorderSide error;

  @override
  InputBorder resolve(Set<WidgetState> states) => CruInputBorder(
    radius: radius,
    borderSide: states.contains(WidgetState.error)
        ? error
        : states.contains(WidgetState.focused)
        ? focused
        : rest,
  );

  @override
  bool operator ==(Object other) =>
      other is CruStateInputBorder &&
      other.rest == rest &&
      other.focused == focused &&
      other.error == error &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(runtimeType, rest, focused, error, radius);
}
