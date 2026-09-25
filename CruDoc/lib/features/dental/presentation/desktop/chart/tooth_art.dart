import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_anatomy.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// ================================================================== look

/// How a tooth's canals show in the endo view.
enum CanalState { none, inProgress, obturated }

/// Everything drawn on a tooth besides its anatomy.
@immutable
class ToothLook {
  const ToothLook({
    this.missing = false,
    this.implant = false,
    this.capped = false,
    this.rootCanal = false,
    this.fractured = false,
    this.impacted = false,
    this.unerupted = false,
    this.decay = const {},
    this.filled = const {},
    this.planned = const [],
    this.pulp = false,
    this.canals = CanalState.none,
    this.lesion = false,
    this.inflamed = false,
    this.dim = false,
  });

  final bool missing;
  final bool implant;

  /// A crown (or a bridge) covers it.
  final bool capped;
  final bool rootCanal;
  final bool fractured;
  final bool impacted;
  final bool unerupted;

  /// Surfaces with decay, and with fillings.
  final Set<ToothSurface> decay;
  final Set<ToothSurface> filled;

  /// Work still to do: what each planned procedure leaves on the tooth
  /// (null when a procedure doesn't map to one).
  final List<ToothTreatment?> planned;

  /// Endo view: the pulp and canals show through.
  final bool pulp;
  final CanalState canals;

  /// Endo view: infection at the root tip.
  final bool lesion;

  /// Endo view: the pulp is inflamed or dead.
  final bool inflamed;

  /// Stepped back (plan view, nothing planned here).
  final bool dim;
}

// ================================================================= forms

/// How one tooth is shaped from the cheek side, as fractions of its
/// half-width (x, mesial positive) and crown height (y, from the biting
/// edge towards the root).
class _Form {
  const _Form({
    required this.edge,
    this.contactM = 0.25,
    this.contactD = 0.3,
    this.cervix = 0.74,
    this.cejSide = 0.9,
    this.cejDip = 0.08,
    this.legs = 1,
    this.sep = 0,
    this.leg = 0.7,
    this.trunk = 0,
    this.curve = 0.08,
    this.flare = 0,
    this.back = false,
    this.grooves = const [],
    this.ridge,
  });

  /// The biting edge, distal to mesial.
  final List<Offset> edge;

  /// Where the crown is widest (touches its neighbours).
  final double contactM;
  final double contactD;

  /// Crown half-width at the neck.
  final double cervix;

  /// The neck (CEJ) at the sides, and how far it dips rootwards mid-tooth.
  final double cejSide;
  final double cejDip;

  /// Roots seen from the cheek: one, or two legs [sep] apart that split
  /// [trunk] (fraction of the root length) below the neck.
  final int legs;
  final double sep;
  final double leg;
  final double trunk;

  /// Apical bend towards distal (fraction of the root length).
  final double curve;

  /// Milk molar roots spread apart.
  final double flare;

  /// A palatal root shows behind (upper molars).
  final bool back;

  /// Grooves on the cheek face.
  final List<List<Offset>> grooves;

  /// The lit ridge down the face of canines and premolars (x).
  final double? ridge;

  _Form copyWith({
    double? cervix,
    double? cejDip,
    int? legs,
    double? sep,
    double? leg,
    double? trunk,
    double? curve,
    double? flare,
  }) =>
      _Form(
        edge: edge,
        contactM: contactM,
        contactD: contactD,
        cervix: cervix ?? this.cervix,
        cejSide: cejSide,
        cejDip: cejDip ?? this.cejDip,
        legs: legs ?? this.legs,
        sep: sep ?? this.sep,
        leg: leg ?? this.leg,
        trunk: trunk ?? this.trunk,
        curve: curve ?? this.curve,
        flare: flare ?? this.flare,
        back: back,
        grooves: grooves,
        ridge: ridge,
      );
}

/// The biting surface seen from above, as fractions of the half-widths
/// (x mesiodistal, mesial positive; y buccolingual, cheek side negative).
class _Occ {
  const _Occ({
    required this.outline,
    this.cusps = const [],
    this.grooves = const [],
    this.ridges = const [],
    this.pits = const [],
    this.incisal,
    this.cingulum,
  });

  final List<Offset> outline;

  /// Cusp tips and their size (x, y, radius).
  final List<(double, double, double)> cusps;
  final List<List<Offset>> grooves;

  /// Lit ridges (a canine's cusp ridges, an upper molar's oblique ridge).
  final List<List<Offset>> ridges;
  final List<Offset> pits;

  /// Front teeth: the biting edge and the bulge behind it.
  final List<Offset>? incisal;
  final Offset? cingulum;
}

List<Offset> _pts(List<double> v) =>
    [for (var i = 0; i < v.length; i += 2) Offset(v[i], v[i + 1])];

_Form _formOf(ToothSpec s) {
  if (!s.primary) return _permanent(s.upper, s.position);
  final p = s.position;
  final base = switch (p) {
    1 || 2 || 3 => _permanent(s.upper, p),
    4 => _permanent(s.upper, s.upper ? 4 : 7),
    _ => _permanent(s.upper, 6),
  };
  // Milk teeth: bulbous necks, thin roots; molar roots splay wide.
  return p >= 4
      ? base.copyWith(
          cervix: math.min(0.86, base.cervix + 0.06),
          cejDip: base.cejDip * 0.6,
          legs: 2,
          sep: 0.6,
          leg: 0.2,
          trunk: 0.1,
          curve: 0,
          flare: 0.24,
        )
      : base.copyWith(
          cervix: math.min(0.84, base.cervix + 0.06),
          leg: base.leg * 0.86,
          curve: 0.12,
        );
}

_Form _permanent(bool upper, int p) {
  if (upper) {
    return switch (p) {
      1 => _Form(
          edge: _pts([-0.94, 0.11, -0.72, 0.035, -0.35, 0.004, 0.2, 0, 0.66, 0.006, 0.93, 0.04]),
          contactM: 0.12,
          contactD: 0.22,
          cervix: 0.76,
          cejSide: 0.88,
          cejDip: 0.13,
          leg: 0.74,
          curve: 0.05,
          grooves: [
            _pts([0.36, 0.05, 0.33, 0.22, 0.3, 0.42]),
            _pts([-0.36, 0.05, -0.33, 0.22, -0.3, 0.42]),
          ],
        ),
      2 => _Form(
          edge: _pts([-0.9, 0.18, -0.62, 0.05, -0.2, 0, 0.35, 0, 0.72, 0.04, 0.94, 0.12]),
          contactM: 0.18,
          contactD: 0.3,
          cervix: 0.72,
          cejSide: 0.88,
          cejDip: 0.12,
          leg: 0.7,
          curve: 0.14,
          grooves: [
            _pts([0.34, 0.06, 0.3, 0.4]),
            _pts([-0.34, 0.07, -0.3, 0.4]),
          ],
        ),
      3 => _Form(
          edge: _pts([-0.99, 0.38, -0.68, 0.22, -0.3, 0.08, 0.06, 0, 0.4, 0.09, 0.74, 0.19, 0.98, 0.27]),
          contactM: 0.3,
          contactD: 0.42,
          cervix: 0.7,
          cejSide: 0.88,
          cejDip: 0.12,
          leg: 0.72,
          curve: 0.07,
          ridge: 0.06,
        ),
      4 => _Form(
          edge: _pts([-0.98, 0.3, -0.62, 0.12, -0.18, 0, 0.3, 0.09, 0.72, 0.2, 0.99, 0.29]),
          contactM: 0.3,
          contactD: 0.32,
          cervix: 0.7,
          cejSide: 0.9,
          cejDip: 0.07,
          legs: 2,
          sep: 0.31,
          leg: 0.31,
          trunk: 0.5,
          curve: 0.05,
          ridge: -0.18,
        ),
      5 => _Form(
          edge: _pts([-0.98, 0.27, -0.55, 0.09, -0.05, 0, 0.5, 0.08, 0.98, 0.25]),
          contactM: 0.28,
          contactD: 0.3,
          cervix: 0.7,
          cejSide: 0.9,
          cejDip: 0.06,
          leg: 0.66,
          curve: 0.08,
          ridge: -0.05,
        ),
      6 => _Form(
          edge: _pts([-0.98, 0.26, -0.8, 0.1, -0.5, 0.01, -0.2, 0.08, -0.06, 0.15, 0.08, 0.08, 0.42, 0, 0.78, 0.08, 0.99, 0.22]),
          contactM: 0.25,
          contactD: 0.3,
          cervix: 0.8,
          cejSide: 0.92,
          cejDip: 0.05,
          legs: 2,
          sep: 0.5,
          leg: 0.3,
          trunk: 0.3,
          curve: 0.12,
          back: true,
          grooves: [_pts([-0.06, 0.15, -0.04, 0.32, -0.02, 0.5])],
        ),
      7 => _Form(
          edge: _pts([-0.97, 0.28, -0.76, 0.12, -0.52, 0.05, -0.28, 0.1, -0.16, 0.16, 0, 0.08, 0.38, 0, 0.76, 0.08, 0.99, 0.22]),
          contactM: 0.26,
          contactD: 0.32,
          cervix: 0.8,
          cejSide: 0.92,
          cejDip: 0.05,
          legs: 2,
          sep: 0.42,
          leg: 0.3,
          trunk: 0.38,
          curve: 0.2,
          back: true,
          grooves: [_pts([-0.16, 0.16, -0.14, 0.32, -0.12, 0.48])],
        ),
      _ => _Form(
          edge: _pts([-0.93, 0.32, -0.66, 0.12, -0.35, 0.05, -0.15, 0.12, 0.12, 0.03, 0.5, 0, 0.86, 0.12]),
          contactM: 0.28,
          contactD: 0.4,
          cervix: 0.78,
          cejSide: 0.9,
          cejDip: 0.05,
          legs: 2,
          sep: 0.3,
          leg: 0.32,
          trunk: 0.55,
          curve: 0.28,
          grooves: [_pts([-0.15, 0.12, -0.12, 0.26, -0.1, 0.4])],
        ),
    };
  }
  return switch (p) {
    1 => _Form(
        edge: _pts([-0.93, 0.03, -0.5, 0, 0.5, 0, 0.93, 0.02]),
        contactM: 0.1,
        contactD: 0.12,
        cervix: 0.72,
        cejSide: 0.88,
        cejDip: 0.1,
        leg: 0.66,
        curve: 0.04,
        grooves: [
          _pts([0.3, 0.06, 0.28, 0.36]),
          _pts([-0.3, 0.06, -0.28, 0.36]),
        ],
      ),
    2 => _Form(
        edge: _pts([-0.92, 0.06, -0.5, 0, 0.5, 0, 0.94, 0.03]),
        contactM: 0.12,
        contactD: 0.18,
        cervix: 0.72,
        cejSide: 0.88,
        cejDip: 0.1,
        leg: 0.68,
        curve: 0.06,
        grooves: [
          _pts([0.3, 0.06, 0.28, 0.36]),
          _pts([-0.3, 0.07, -0.28, 0.36]),
        ],
      ),
    3 => _Form(
        edge: _pts([-0.99, 0.32, -0.6, 0.15, -0.2, 0.04, 0.14, 0, 0.52, 0.08, 0.92, 0.16]),
        contactM: 0.18,
        contactD: 0.36,
        cervix: 0.7,
        cejSide: 0.9,
        cejDip: 0.1,
        leg: 0.7,
        curve: 0.06,
        ridge: 0.12,
      ),
    4 => _Form(
        edge: _pts([-0.97, 0.34, -0.55, 0.13, -0.05, 0, 0.45, 0.11, 0.96, 0.3]),
        contactM: 0.32,
        contactD: 0.34,
        cervix: 0.66,
        cejSide: 0.9,
        cejDip: 0.07,
        leg: 0.62,
        curve: 0.07,
        ridge: -0.04,
      ),
    5 => _Form(
        edge: _pts([-0.98, 0.28, -0.52, 0.09, 0, 0.02, 0.52, 0.08, 0.98, 0.26]),
        contactM: 0.3,
        contactD: 0.3,
        cervix: 0.68,
        cejSide: 0.9,
        cejDip: 0.06,
        leg: 0.64,
        curve: 0.08,
        ridge: 0,
      ),
    6 => _Form(
        edge: _pts([-0.99, 0.25, -0.86, 0.11, -0.68, 0.06, -0.52, 0.12, -0.34, 0.04, -0.1, 0, 0.12, 0.06, 0.22, 0.12, 0.36, 0.05, 0.58, 0, 0.86, 0.08, 1, 0.2]),
        contactM: 0.22,
        contactD: 0.28,
        cervix: 0.84,
        cejSide: 0.9,
        cejDip: 0.05,
        legs: 2,
        sep: 0.54,
        leg: 0.3,
        trunk: 0.22,
        curve: 0.1,
        grooves: [
          _pts([0.22, 0.12, 0.21, 0.3, 0.2, 0.5]),
          _pts([-0.52, 0.12, -0.51, 0.28, -0.5, 0.45]),
        ],
      ),
    7 => _Form(
        edge: _pts([-0.98, 0.24, -0.72, 0.07, -0.42, 0, -0.1, 0.08, 0.02, 0.14, 0.15, 0.07, 0.48, 0, 0.8, 0.07, 0.99, 0.2]),
        contactM: 0.22,
        contactD: 0.28,
        cervix: 0.84,
        cejSide: 0.9,
        cejDip: 0.05,
        legs: 2,
        sep: 0.46,
        leg: 0.3,
        trunk: 0.3,
        curve: 0.18,
        grooves: [_pts([0.02, 0.14, 0.02, 0.32, 0.02, 0.5])],
      ),
    _ => _Form(
        edge: _pts([-0.95, 0.28, -0.66, 0.08, -0.3, 0.02, -0.05, 0.1, 0.2, 0.03, 0.55, 0, 0.88, 0.12]),
        contactM: 0.24,
        contactD: 0.34,
        cervix: 0.8,
        cejSide: 0.9,
        cejDip: 0.05,
        legs: 2,
        sep: 0.32,
        leg: 0.32,
        trunk: 0.45,
        curve: 0.3,
        grooves: [_pts([-0.05, 0.1, -0.04, 0.26, -0.03, 0.42])],
      ),
  };
}

_Occ _occOf(ToothSpec s) {
  var p = s.position;
  if (s.primary) {
    p = switch (p) {
      1 || 2 || 3 => p,
      4 => s.upper ? 4 : 7,
      _ => 6,
    };
  }
  if (s.upper) {
    return switch (p) {
      1 => _Occ(
          outline: _pts([0.96, -0.46, 0.74, -0.86, 0.25, -1, -0.3, -0.98, -0.76, -0.84, -0.97, -0.44, -0.8, 0.18, -0.45, 0.72, 0, 1, 0.45, 0.72, 0.8, 0.18]),
          incisal: _pts([-0.88, -0.55, -0.3, -0.66, 0.3, -0.66, 0.9, -0.57]),
          cingulum: const Offset(0, 0.64),
        ),
      2 => _Occ(
          outline: _pts([0.95, -0.4, 0.7, -0.86, 0.2, -1, -0.3, -0.97, -0.75, -0.8, -0.96, -0.36, -0.78, 0.25, -0.4, 0.76, 0, 1, 0.42, 0.76, 0.8, 0.25]),
          incisal: _pts([-0.84, -0.5, -0.3, -0.62, 0.3, -0.62, 0.86, -0.52]),
          cingulum: const Offset(0, 0.62),
        ),
      3 => _Occ(
          outline: _pts([1, -0.22, 0.66, -0.74, 0.12, -1, -0.45, -0.82, -0.98, -0.26, -0.78, 0.3, -0.36, 0.8, 0.04, 1, 0.4, 0.8, 0.8, 0.32]),
          cusps: [(0.05, -0.36, 0.55)],
          ridges: [
            _pts([0.05, -0.36, 0.5, -0.3, 0.92, -0.24]),
            _pts([0.05, -0.36, -0.45, -0.32, -0.9, -0.28]),
            _pts([0.05, -0.36, 0.04, 0.2, 0.03, 0.72]),
          ],
        ),
      4 => _Occ(
          outline: _pts([1, -0.02, 0.9, -0.62, 0.52, -0.95, 0, -1, -0.52, -0.95, -0.9, -0.62, -1, -0.02, -0.86, 0.6, -0.45, 0.94, 0.05, 1, 0.5, 0.93, 0.88, 0.58]),
          cusps: [(0, -0.46, 0.55), (0.08, 0.5, 0.45)],
          grooves: [
            _pts([0.66, 0.02, 0.3, -0.03, -0.3, -0.03, -0.66, 0.02]),
            _pts([0.66, 0.02, 0.98, 0.06]),
          ],
          pits: _pts([0.66, 0.02, -0.66, 0.02]),
        ),
      5 => _Occ(
          outline: _pts([1, 0, 0.88, -0.64, 0.48, -0.96, 0, -1, -0.48, -0.96, -0.88, -0.64, -1, 0, -0.88, 0.62, -0.48, 0.96, 0, 1, 0.48, 0.96, 0.88, 0.62]),
          cusps: [(0, -0.44, 0.5), (0, 0.46, 0.48)],
          grooves: [
            _pts([0.48, 0, 0, 0.02, -0.48, 0]),
            _pts([0.2, 0.01, 0.35, -0.22]),
            _pts([-0.2, 0.01, -0.35, 0.22]),
          ],
          pits: _pts([0.48, 0, -0.48, 0]),
        ),
      6 => _Occ(
          outline: _pts([1, 0, 0.97, -0.55, 0.72, -0.94, 0.1, -1, -0.55, -0.96, -0.94, -0.62, -1, -0.05, -0.9, 0.5, -0.56, 0.9, -0.02, 1, 0.52, 0.96, 0.88, 0.62]),
          cusps: [(0.46, -0.5, 0.42), (-0.44, -0.52, 0.36), (0.36, 0.42, 0.5), (-0.5, 0.56, 0.32)],
          grooves: [
            _pts([0.72, -0.06, 0.38, -0.04, 0.04, 0]),
            _pts([0.04, 0, -0.02, -0.48, 0.02, -0.98]),
            _pts([-0.66, 0.1, -0.42, 0.36, -0.16, 0.98]),
            _pts([0.04, 0, -0.14, 0.12]),
          ],
          ridges: [_pts([0.3, 0.36, -0.06, -0.06, -0.38, -0.44])],
          pits: _pts([0.72, -0.06, 0.04, 0, -0.66, 0.1]),
        ),
      7 => _Occ(
          outline: _pts([1, 0, 0.96, -0.52, 0.7, -0.94, 0.08, -1, -0.56, -0.9, -0.95, -0.5, -0.96, 0.15, -0.74, 0.7, -0.28, 0.98, 0.32, 0.98, 0.84, 0.64]),
          cusps: [(0.45, -0.5, 0.42), (-0.4, -0.5, 0.34), (0.34, 0.4, 0.5), (-0.52, 0.45, 0.22)],
          grooves: [
            _pts([0.72, -0.05, 0.38, -0.03, 0.04, 0]),
            _pts([0.04, 0, -0.02, -0.5, 0, -0.98]),
            _pts([-0.6, 0.1, -0.4, 0.3, -0.2, 0.95]),
          ],
          ridges: [_pts([0.28, 0.34, -0.06, -0.04, -0.34, -0.42])],
          pits: _pts([0.72, -0.05, 0.04, 0, -0.6, 0.1]),
        ),
      _ => _Occ(
          outline: _pts([1, -0.02, 0.9, -0.6, 0.5, -0.96, -0.1, -1, -0.66, -0.8, -0.98, -0.25, -0.86, 0.42, -0.4, 0.9, 0.2, 0.98, 0.72, 0.72]),
          cusps: [(0.4, -0.45, 0.42), (-0.38, -0.42, 0.36), (0.18, 0.45, 0.5)],
          grooves: [
            _pts([0.62, -0.08, 0.05, 0, -0.55, 0.05]),
            _pts([0.05, 0, 0, -0.95]),
            _pts([0.05, 0, -0.3, 0.45, -0.4, 0.85]),
          ],
          pits: _pts([0.62, -0.08, 0.05, 0, -0.55, 0.05]),
        ),
    };
  }
  return switch (p) {
    1 => _Occ(
        outline: _pts([0.96, -0.46, 0.66, -0.88, 0, -1, -0.66, -0.88, -0.96, -0.46, -0.9, 0.16, -0.56, 0.74, 0, 1, 0.56, 0.74, 0.9, 0.16]),
        incisal: _pts([-0.86, -0.4, 0, -0.48, 0.86, -0.4]),
        cingulum: const Offset(0, 0.6),
      ),
    2 => _Occ(
        outline: _pts([0.96, -0.44, 0.66, -0.88, 0, -1, -0.7, -0.86, -0.98, -0.42, -0.9, 0.2, -0.54, 0.76, 0.02, 1, 0.56, 0.72, 0.9, 0.14]),
        incisal: _pts([-0.88, -0.36, 0, -0.46, 0.86, -0.42]),
        cingulum: const Offset(0, 0.6),
      ),
    3 => _Occ(
        outline: _pts([1, -0.24, 0.62, -0.8, 0.1, -1, -0.5, -0.82, -0.98, -0.3, -0.8, 0.34, -0.36, 0.84, 0.06, 1, 0.44, 0.8, 0.82, 0.3]),
        cusps: [(0.1, -0.34, 0.5)],
        ridges: [
          _pts([0.1, -0.34, 0.52, -0.3, 0.94, -0.26]),
          _pts([0.1, -0.34, -0.42, -0.34, -0.92, -0.32]),
          _pts([0.1, -0.34, 0.08, 0.2, 0.06, 0.72]),
        ],
      ),
    4 => _Occ(
        outline: _pts([1, -0.12, 0.82, -0.7, 0.36, -1, -0.34, -1, -0.82, -0.7, -1, -0.12, -0.72, 0.5, -0.28, 0.9, 0.3, 0.9, 0.72, 0.5]),
        cusps: [(0, -0.3, 0.64), (0.04, 0.58, 0.3)],
        ridges: [_pts([0, -0.3, 0.02, 0.1, 0.04, 0.52])],
        grooves: [
          _pts([0.44, 0.12, 0.68, 0.28]),
          _pts([-0.44, 0.12, -0.68, 0.28]),
        ],
        pits: _pts([0.44, 0.12, -0.44, 0.12]),
      ),
    5 => _Occ(
        outline: _pts([1, -0.1, 0.86, -0.72, 0.36, -1, -0.36, -1, -0.86, -0.72, -1, -0.1, -0.9, 0.55, -0.46, 0.95, 0.46, 0.95, 0.9, 0.55]),
        cusps: [(0, -0.42, 0.52), (0.44, 0.5, 0.32), (-0.42, 0.52, 0.28)],
        grooves: [
          _pts([0.6, -0.02, 0.02, 0.12, -0.6, -0.02]),
          _pts([0.02, 0.12, 0.06, 0.92]),
        ],
        pits: _pts([0.02, 0.12, 0.6, -0.02, -0.6, -0.02]),
      ),
    6 => _Occ(
        outline: _pts([1, -0.14, 0.86, -0.8, 0.34, -1, -0.3, -0.98, -0.8, -0.76, -1, -0.2, -0.92, 0.5, -0.52, 0.95, 0.24, 1, 0.8, 0.86, 1, 0.36]),
        cusps: [(0.52, -0.5, 0.38), (-0.06, -0.55, 0.36), (-0.64, -0.3, 0.28), (0.5, 0.5, 0.38), (-0.32, 0.52, 0.36)],
        grooves: [
          _pts([0.76, 0, 0.26, 0.06, -0.06, 0.02, -0.42, 0.06, -0.74, 0.02]),
          _pts([0.26, 0.06, 0.2, -0.5, 0.22, -0.97]),
          _pts([-0.42, 0.06, -0.44, -0.44, -0.56, -0.86]),
          _pts([-0.06, 0.02, 0.04, 0.5, 0.08, 0.99]),
        ],
        pits: _pts([0.76, 0, -0.06, 0.02, -0.74, 0.02]),
      ),
    7 => _Occ(
        outline: _pts([1, -0.1, 0.88, -0.8, 0.3, -1, -0.36, -1, -0.88, -0.78, -1, -0.1, -0.9, 0.62, -0.36, 1, 0.36, 1, 0.9, 0.64]),
        cusps: [(0.48, -0.5, 0.42), (-0.46, -0.5, 0.4), (0.48, 0.5, 0.42), (-0.46, 0.5, 0.4)],
        grooves: [
          _pts([0.76, 0, 0, 0.02, -0.76, 0]),
          _pts([0, 0.02, 0, -0.97]),
          _pts([0, 0.02, 0, 0.97]),
        ],
        pits: _pts([0.76, 0, 0, 0.02, -0.76, 0]),
      ),
    _ => _Occ(
        outline: _pts([1, -0.1, 0.84, -0.78, 0.3, -1, -0.4, -0.96, -0.9, -0.66, -0.98, 0, -0.84, 0.66, -0.34, 1, 0.36, 0.98, 0.88, 0.66]),
        cusps: [(0.46, -0.48, 0.4), (-0.44, -0.46, 0.38), (0.44, 0.5, 0.4), (-0.42, 0.5, 0.36)],
        grooves: [
          _pts([0.74, 0, 0.3, 0.04, 0, 0.02, -0.3, 0, -0.72, 0.02]),
          _pts([0, 0.02, 0.02, -0.96]),
          _pts([0, 0.02, -0.02, 0.96]),
          _pts([0.3, 0.04, 0.42, -0.36]),
          _pts([-0.3, 0, -0.36, 0.38]),
        ],
        pits: _pts([0.74, 0, 0, 0.02, -0.72, 0.02]),
      ),
  };
}

// ================================================================ shapes

/// A tooth seen from the cheek side, in screen space: mesial towards the
/// midline, the biting edge towards the bite.
class BuccalShape {
  BuccalShape._(this.spec, this.k, this.cx, this.edgeY, this._f);

  /// [edgeY] is the biting edge's y; upper teeth hang from it with their
  /// roots up, lower teeth stand on it with their roots down.
  factory BuccalShape.of(
    ToothSpec spec, {
    required double k,
    required double cx,
    required double edgeY,
  }) =>
      BuccalShape._(spec, k, cx, edgeY, _formOf(spec));

  final ToothSpec spec;

  /// Pixels per millimetre.
  final double k;
  final double cx;
  final double edgeY;
  final _Form _f;

  bool get upper => spec.upper;
  bool get mirror => !spec.patientRight;
  double get _w => spec.md / 2;
  double get _ch => spec.crown;
  double get _rl => spec.root;
  bool get front => spec.kind != ToothKind.premolar && spec.kind != ToothKind.molar;

  /// Screen point of a model point (mm; x mesial, y rootwards).
  Offset at(double x, double y) =>
      Offset(cx + (mirror ? -x : x) * k, edgeY + (upper ? -y : y) * k);

  /// One millimetre towards the root, on screen.
  double get rootward => upper ? -k : k;

  /// The neck's y at [x] (model mm).
  double cejY(double x) {
    final u = (x / (_f.cervix * _w)).clamp(-1.0, 1.0);
    return (_f.cejSide + _f.cejDip * (1 - u * u)) * _ch;
  }

  // ------------------------------------------------------------ crown

  /// The neck's corners, where crown, root and outline meet.
  late final Offset _neckM = Offset(_f.cervix * _w, cejY(_f.cervix * _w));
  late final Offset _neckD = Offset(-_f.cervix * _w, cejY(-_f.cervix * _w));

  late final Path crown = () {
    final f = _f;
    final w = _w, ch = _ch;
    Offset side(double contact, double t, double sign) => Offset(
          sign * (1 - (1 - f.cervix) * math.pow(t, 1.15)) * w,
          (contact + (f.cejSide - contact) * t) * ch,
        );
    // Up the mesial side, over the biting edge, down the distal side.
    final over = [
      _neckM,
      side(f.contactM, 0.93, 1),
      side(f.contactM, 0.7, 1),
      side(f.contactM, 0.36, 1),
      if (f.contactM > f.edge.last.dy + 0.04) Offset(w, f.contactM * ch),
      for (final e in f.edge.reversed) Offset(e.dx * w, e.dy * ch),
      if (f.contactD > f.edge.first.dy + 0.04) Offset(-w, f.contactD * ch),
      side(f.contactD, 0.36, -1),
      side(f.contactD, 0.7, -1),
      side(f.contactD, 0.93, -1),
      _neckD,
    ];
    // Back along the neck, dipping rootwards in the middle.
    final neck = [
      for (final u in const [-1.0, -0.55, 0.0, 0.55, 1.0])
        Offset(u * f.cervix * w, cejY(u * f.cervix * w)),
    ];
    final first = at(over.first.dx, over.first.dy);
    final path = Path()..moveTo(first.dx, first.dy);
    appendSmooth(path, [for (final p in over) at(p.dx, p.dy)]);
    appendSmooth(path, [for (final p in neck) at(p.dx, p.dy)]);
    return path..close();
  }();

  late final Rect crownRect = crown.getBounds();

  /// The neck line, distal to mesial.
  late final List<Offset> neck = [
    for (final u in const [-1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0])
      at(u * _f.cervix * _w, cejY(u * _f.cervix * _w)),
  ];

  /// Grooves and the lit ridge on the cheek face.
  late final List<List<Offset>> grooves = [
    for (final g in _f.grooves) [for (final p in g) at(p.dx * _w, p.dy * _ch)],
  ];
  late final List<Offset>? ridge = _f.ridge == null
      ? null
      : [
          at(_f.ridge! * _w, 0.08 * _ch),
          at(_f.ridge! * _w * 0.7, 0.36 * _ch),
          at(_f.ridge! * _w * 0.4, 0.68 * _ch),
        ];

  // ------------------------------------------------------------ roots

  double _curveAt(double t) => -_f.curve * _rl * math.pow(t, 2.4);

  late final double _neck = _f.cejSide * _ch;
  late final double _r0 = _f.cervix * _w;

  /// Centre of a root leg at [t] (0 at the fork, 1 at the tip); side is
  /// +1 for the mesial leg, -1 for the distal one.
  Offset _legC(int side, double t) {
    final yF = _neck + _f.trunk * _rl;
    final x = side * _f.sep * _w +
        side * _f.flare * _w * math.pow(t, 1.4) +
        _curveAt(t);
    return Offset(x, yF + t * _rl * (1 - _f.trunk));
  }

  double _legHalf(double t) => _f.leg * _w * (1 - 0.8 * math.pow(t, 1.5));

  /// The roots' outline from the mesial neck corner round to the distal
  /// one; the top is closed out of sight under the crown.
  late final List<Offset> _rootModel = () {
    if (_f.legs == 1) {
      double half(double t) => _r0 * (1 - 0.86 * math.pow(t, 1.6));
      const ts = [0.28, 0.55, 0.8, 0.94];
      return [
        _neckM,
        for (final t in ts) Offset(_curveAt(t) + half(t), _neck + t * _rl),
        Offset(_curveAt(1), _neck + _rl),
        for (final t in ts.reversed) Offset(_curveAt(t) - half(t), _neck + t * _rl),
        _neckD,
      ];
    }
    const down = [0.3, 0.6, 0.85, 0.96];
    const up = [0.85, 0.6, 0.3];
    final m0 = _legC(1, 0), d0 = _legC(-1, 0);
    final crotch = Offset(((m0.dx - _legHalf(0)) + (d0.dx + _legHalf(0))) / 2, m0.dy);
    return [
      _neckM,
      if (_f.trunk > 0.18) Offset(m0.dx + _legHalf(0), m0.dy),
      for (final t in down) _legC(1, t).translate(_legHalf(t), 0),
      _legC(1, 1),
      for (final t in up) _legC(1, t).translate(-_legHalf(t), 0),
      crotch,
      for (final t in up.reversed) _legC(-1, t).translate(_legHalf(t), 0),
      _legC(-1, 1),
      for (final t in down.reversed) _legC(-1, t).translate(-_legHalf(t), 0),
      if (_f.trunk > 0.18) Offset(d0.dx - _legHalf(0), d0.dy),
      _neckD,
    ];
  }();

  late final Path roots = () {
    final pts = [for (final p in _rootModel) at(p.dx, p.dy)];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    appendSmooth(path, pts);
    final top = (_f.cejSide - 0.3) * _ch;
    final inner = _f.cervix * _w * 0.8;
    final a = at(-inner, top), b = at(inner, top);
    return path
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
  }();

  /// The palatal root, behind the others (upper molars).
  late final Path? backRoot = !_f.back
      ? null
      : () {
          final yTop = _neck + _f.trunk * _rl * 0.6;
          final len = _rl * 1.04 - (yTop - _neck);
          final r0 = _w * 0.34;
          double half(double t) => r0 * (1 - 0.8 * math.pow(t, 1.6));
          double x(double t) => _w * 0.06 + _curveAt(t) * 0.5;
          const ts = [0.3, 0.6, 0.85, 0.96];
          return smoothClosed([
            for (final p in [
              Offset(x(0) + r0, yTop - _ch * 0.2),
              for (final t in ts) Offset(x(t) + half(t), yTop + t * len),
              Offset(x(1), yTop + len),
              for (final t in ts.reversed) Offset(x(t) - half(t), yTop + t * len),
              Offset(x(0) - r0, yTop - _ch * 0.2),
            ])
              at(p.dx, p.dy),
          ]);
        }();

  /// Canal centre lines, from the pulp chamber to each root tip.
  late final List<List<Offset>> canals = () {
    final floor = _neck - _ch * 0.02;
    if (_f.legs == 1) {
      return [
        [
          at(0, front ? 0.34 * _ch : floor),
          at(_curveAt(0.02), _neck + 0.02 * _rl),
          at(_curveAt(0.5), _neck + 0.5 * _rl),
          at(_curveAt(0.97), _neck + 0.97 * _rl),
        ],
      ];
    }
    return [
      for (final side in const [1, -1])
        [
          at(side * _f.sep * _w * 0.4, floor),
          at(_legC(side, 0).dx, _legC(side, 0).dy),
          at(_legC(side, 0.5).dx, _legC(side, 0.5).dy),
          at(_legC(side, 0.97).dx, _legC(side, 0.97).dy),
        ],
    ];
  }();

  /// Root tips.
  late final List<Offset> apexes = _f.legs == 1
      ? [at(_curveAt(1), _neck + _rl)]
      : [
          at(_legC(1, 1).dx, _legC(1, 1).dy),
          at(_legC(-1, 1).dx, _legC(-1, 1).dy),
        ];

  /// Width of a root (a leg of it) near the neck, in pixels.
  double get rootThickness =>
      (_f.legs == 1 ? _r0 * 2 : _f.leg * _w * 2) * k;

  /// The pulp chamber inside the crown.
  late final Path chamber = () {
    final c = _f.cervix * _w;
    final floor = _neck + (_f.legs == 1 ? 0.02 : 0.06) * _ch;
    final pts = front
        ? [
            Offset(0, 0.3 * _ch),
            Offset(c * 0.34, 0.58 * _ch),
            Offset(c * 0.3, floor),
            Offset(0, floor + 0.03 * _ch),
            Offset(-c * 0.3, floor),
            Offset(-c * 0.34, 0.58 * _ch),
          ]
        : [
            Offset(c * 0.5, 0.38 * _ch),
            Offset(c * 0.58, 0.62 * _ch),
            Offset(c * 0.48, floor),
            Offset(0, floor + 0.05 * _ch),
            Offset(-c * 0.48, floor),
            Offset(-c * 0.58, 0.62 * _ch),
            Offset(-c * 0.5, 0.4 * _ch),
            Offset(-c * 0.2, 0.5 * _ch),
            Offset(c * 0.2, 0.5 * _ch),
          ];
    return smoothClosed([for (final p in pts) at(p.dx, p.dy)]);
  }();

  /// Where a molar's roots fork.
  Offset? get furcation => _f.legs == 1
      ? null
      : at((_legC(1, 0).dx + _legC(-1, 0).dx) / 2, _neck + _f.trunk * _rl);

  late final Rect bounds = crownRect.expandToInclude(roots.getBounds());

  /// The whole tooth's outline (for rings and hit tests).
  late final Path silhouette = Path.combine(PathOperation.union, crown, roots);

  // --------------------------------------------------------- surfaces

  /// Where each surface sits on the cheek-side face (the tongue side
  /// isn't visible from here).
  Rect? surfaceArea(ToothSurface s) {
    final w = _w, ch = _ch;
    Rect ellipse(double x, double y, double rx, double ry) => Rect.fromCenter(
          center: at(x, y),
          width: rx * 2 * k,
          height: ry * 2 * k,
        );
    return switch (s) {
      ToothSurface.mesial => ellipse(0.7 * w, 0.3 * ch, 0.34 * w, 0.36 * ch),
      ToothSurface.distal => ellipse(-0.7 * w, 0.32 * ch, 0.34 * w, 0.36 * ch),
      ToothSurface.buccal => ellipse(0, 0.56 * ch, 0.42 * w, 0.24 * ch),
      ToothSurface.occlusal ||
      ToothSurface.incisal =>
        ellipse(0, 0.02 * ch, 0.8 * w, 0.14 * ch),
      ToothSurface.cervical =>
        ellipse(0, cejY(0) - 0.1 * ch, 0.64 * w, 0.1 * ch),
      ToothSurface.lingual => null,
    };
  }

  /// A crack across the crown.
  late final List<Offset> crack = [
    at(-0.56 * _w, 0.04 * _ch),
    at(-0.22 * _w, 0.2 * _ch),
    at(-0.3 * _w, 0.32 * _ch),
    at(0.04 * _w, 0.5 * _ch),
    at(-0.04 * _w, 0.6 * _ch),
  ];

  /// An implant fixture in place of the roots, and its thread lines.
  late final Path implant = () {
    final top = _neck - _ch * 0.1;
    final len = _rl * 0.86;
    final r = _f.cervix * _w * 0.62;
    return smoothClosed([
      for (final p in [
        Offset(r, top),
        Offset(r * 0.98, top + len * 0.5),
        Offset(r * 0.8, top + len * 0.9),
        Offset(r * 0.4, top + len),
        Offset(-r * 0.4, top + len),
        Offset(-r * 0.8, top + len * 0.9),
        Offset(-r * 0.98, top + len * 0.5),
        Offset(-r, top),
      ])
        at(p.dx, p.dy),
    ]);
  }();

  late final List<(Offset, Offset)> threads = () {
    final top = _neck + _ch * 0.1;
    final len = _rl * 0.74;
    final r = _f.cervix * _w * 0.62;
    const n = 8;
    return [
      for (var i = 0; i < n; i++)
        () {
          final y = top + len * i / n;
          final half = r * (1 - 0.3 * math.pow(i / n, 2));
          return (at(-half, y), at(half, y + len / n * 0.5));
        }(),
    ];
  }();

  /// Gum sites on the cheek side (distal, middle, mesial), at the neck.
  Offset site(int i) {
    final x = switch (i) { 0 => -0.62 * _w, 1 => 0.0, _ => 0.62 * _w };
    return at(x, cejY(x));
  }
}

/// A tooth's biting surface seen from above (upper teeth from below), in
/// screen space: cheek side towards the tooth's cheek-side view.
class OcclusalShape {
  OcclusalShape._(this.spec, this.k, this.center, this._o);

  factory OcclusalShape.of(ToothSpec spec, {required double k, required Offset center}) =>
      OcclusalShape._(spec, k, center, _occOf(spec));

  final ToothSpec spec;
  final double k;
  final Offset center;
  final _Occ _o;

  bool get mirror => !spec.patientRight;
  bool get upper => spec.upper;
  double get _a => spec.md / 2;
  double get _b => spec.bl / 2;
  bool get front => spec.kind != ToothKind.premolar && spec.kind != ToothKind.molar;

  /// Screen point of a model point (fractions of the half-widths).
  Offset at(double x, double y) => Offset(
        center.dx + (mirror ? -x : x) * _a * k,
        center.dy + (upper ? y : -y) * _b * k,
      );

  late final Path outline = smoothClosed([for (final p in _o.outline) at(p.dx, p.dy)]);
  late final Rect rect = outline.getBounds();

  late final List<(Offset, double)> cusps = [
    for (final (x, y, r) in _o.cusps) (at(x, y), r * math.min(_a, _b) * k),
  ];
  late final List<List<Offset>> grooves = [
    for (final g in _o.grooves) [for (final p in g) at(p.dx, p.dy)],
  ];
  late final List<List<Offset>> ridges = [
    for (final g in _o.ridges) [for (final p in g) at(p.dx, p.dy)],
  ];
  late final List<Offset> pits = [for (final p in _o.pits) at(p.dx, p.dy)];
  late final List<Offset>? incisal =
      _o.incisal == null ? null : [for (final p in _o.incisal!) at(p.dx, p.dy)];
  late final Offset? cingulum =
      _o.cingulum == null ? null : at(_o.cingulum!.dx, _o.cingulum!.dy);

  /// Where each surface sits on the biting-surface view.
  Path? surfaceArea(ToothSurface s) {
    Path ellipse(double x, double y, double rx, double ry) => Path()
      ..addOval(Rect.fromCenter(
        center: at(x, y),
        width: rx * 2 * _a * k,
        height: ry * 2 * _b * k,
      ));
    final edgeY = _o.incisal == null
        ? -0.5
        : _o.incisal!.map((p) => p.dy).reduce((a, b) => a + b) / _o.incisal!.length;
    final area = switch (s) {
      ToothSurface.occlusal || ToothSurface.incisal => front
          ? ellipse(0, edgeY, 0.86, 0.17)
          : ellipse(0, 0.02, 0.5, 0.36),
      ToothSurface.mesial => ellipse(0.78, 0, 0.4, 0.42),
      ToothSurface.distal => ellipse(-0.78, 0, 0.4, 0.42),
      ToothSurface.buccal => ellipse(0, -0.8, 0.6, 0.28),
      ToothSurface.lingual => front ? ellipse(0, 0.28, 0.42, 0.34) : ellipse(0, 0.8, 0.56, 0.28),
      ToothSurface.cervical => null,
    };
    return area == null ? null : Path.combine(PathOperation.intersect, area, outline);
  }

  /// A crack across the surface.
  late final List<Offset> crack = [
    at(-0.82, -0.34),
    at(-0.3, -0.06),
    at(-0.1, 0.1),
    at(0.3, 0.2),
    at(0.74, 0.52),
  ];
}

// ================================================================ curves

/// A smooth closed outline through [p] (Catmull-Rom).
Path smoothClosed(List<Offset> p) {
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  final n = p.length;
  for (var i = 0; i < n; i++) {
    final p0 = p[(i - 1 + n) % n];
    final p1 = p[i];
    final p2 = p[(i + 1) % n];
    final p3 = p[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

/// A smooth open line through [p].
Path smoothOpen(List<Offset> p) {
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  if (p.length == 2) return path..lineTo(p[1].dx, p[1].dy);
  appendSmooth(path, p);
  return path;
}

/// Continues [path] (which is at p[0]) smoothly through [p].
void appendSmooth(Path path, List<Offset> p) {
  for (var i = 0; i < p.length - 1; i++) {
    final p0 = p[math.max(0, i - 1)];
    final p1 = p[i];
    final p2 = p[i + 1];
    final p3 = p[math.min(p.length - 1, i + 2)];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
}

/// Strokes [path] in dashes.
void dashPath(Canvas canvas, Path path, Paint paint, {double dash = 4, double gap = 3}) {
  for (final m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      d += dash + gap;
    }
  }
}

// ============================================================== painting

Color _clear(Color c) => c.withValues(alpha: 0);

Paint _blurred(Color color, double sigma) => Paint()
  ..color = color
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.1, sigma));

/// Paints teeth: the anatomy with light and shade, then what was found,
/// what was done and what's planned.
abstract final class ToothArt {
  // ---------------------------------------------------------- buccal

  /// The cheek-side view of one tooth.
  static void buccal(Canvas canvas, BuccalShape s, ToothLook look, CruColors c) {
    canvas.save();
    _pose(canvas, s, look);
    if (look.missing) {
      _ghost(canvas, [s.roots, s.crown], c);
      if (look.implant) _implant(canvas, s, c);
      _plannedBuccal(canvas, s, look, c);
      canvas.restore();
      return;
    }
    final fade = look.dim || look.unerupted;
    if (fade) {
      canvas.saveLayer(
        s.bounds.inflate(s.k * 6),
        Paint()..color = Color.fromRGBO(0, 0, 0, look.dim ? 0.42 : 0.62),
      );
    }

    // Roots, or the implant that replaced them.
    if (look.implant) {
      _implant(canvas, s, c);
    } else {
      if (s.backRoot != null) _root(canvas, s.backRoot!, s, c, back: true);
      _root(canvas, s.roots, s, c);
      if (look.rootCanal && !look.pulp) _canals(canvas, s, c, c.greenText, clip: s.roots);
    }

    // Crown.
    _enamel(canvas, s.crown, s.crownRect, c, biteUp: !s.upper, front: s.front, k: s.k);
    _faceDetail(canvas, s, c);
    // The crown's shadow on the root just below the neck.
    if (!look.implant) {
      canvas.save();
      canvas.clipPath(s.roots);
      canvas.drawPath(
        smoothOpen(s.neck),
        _blurred(c.toothShadow.withValues(alpha: 0.16), s.k * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.k * 0.7,
      );
      canvas.restore();
    }
    canvas.drawPath(
      s.crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _line(s.k)
        ..color = c.enamelEdge.withValues(alpha: 0.8),
    );

    // Found and done.
    if (look.capped) {
      _cap(canvas, s.crown, s.crownRect, c, s.k, neck: s.neck);
    } else {
      final filled = _areas(look.filled.map(s.surfaceArea), s.crown);
      if (filled != null) _restoration(canvas, filled, c, s.k);
    }
    for (final surface in look.decay) {
      final a = s.surfaceArea(surface);
      if (a != null) _lesion(canvas, a, s.crown, c);
    }
    if (look.fractured) _crack(canvas, s.crack, c, s.k);

    // Endo view: the pulp shows through.
    if (look.pulp) _pulp(canvas, s, look, c);
    if (look.impacted) {
      dashPath(
        canvas,
        s.crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = c.amberText,
      );
    }

    if (fade) canvas.restore();
    _plannedBuccal(canvas, s, look, c);
    canvas.restore();
  }

  /// Unerupted teeth sit down in the bone; impacted ones also tip over.
  static void _pose(Canvas canvas, BuccalShape s, ToothLook look) {
    if (!look.unerupted && !look.impacted) return;
    final sink = s.spec.crown * (look.unerupted ? 0.55 : 0.35);
    canvas.translate(0, s.rootward * sink);
    if (look.impacted) {
      final pivot = s.at(0, s.spec.crown + s.spec.root * 0.45);
      // Tip the crown mesially.
      final mesial = (s.at(1, 0) - s.at(0, 0)).dx.sign;
      final down = s.upper ? -1.0 : 1.0;
      final angle = 0.32 * mesial * down;
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(angle);
      canvas.translate(-pivot.dx, -pivot.dy);
    }
  }

  static double _line(double k) => (k * 0.14).clamp(0.7, 1.6);

  /// Enamel: lit from the upper left, rounding away at the sides, warm
  /// near the neck, clear at the biting edge of front teeth.
  static void _enamel(
    Canvas canvas,
    Path p,
    Rect r,
    CruColors c, {
    required bool biteUp,
    required bool front,
    required double k,
  }) {
    canvas.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(
          r.centerLeft,
          r.centerRight,
          [c.enamelShade, c.enamelMid, c.enamel, c.enamel, c.enamelMid, c.enamelShade],
          const [0, 0.16, 0.36, 0.5, 0.8, 1],
        ),
    );
    final edge = Offset(r.center.dx, biteUp ? r.top : r.bottom);
    final neck = Offset(r.center.dx, biteUp ? r.bottom : r.top);
    canvas.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(
          edge,
          neck,
          [
            front ? c.enamelClear.withValues(alpha: 0.75) : _clear(c.enamelClear),
            _clear(c.enamelClear),
            _clear(c.enamelWarm),
            c.enamelWarm.withValues(alpha: 0.6),
          ],
          const [0, 0.26, 0.68, 1],
        ),
    );
    canvas.save();
    canvas.clipPath(p);
    // Rounding away at the outline.
    canvas.drawPath(
      p,
      _blurred(c.toothShadow.withValues(alpha: 0.2), r.width * 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.width * 0.2,
    );
    // Gloss.
    final g = Rect.fromCenter(
      center: Offset(r.left + r.width * 0.36, r.top + r.height * 0.42),
      width: r.width * 0.26,
      height: r.height * 0.46,
    );
    canvas.drawOval(g, _blurred(c.toothGloss.withValues(alpha: 0.85), r.width * 0.07));
    canvas.restore();
  }

  /// Grooves and ridges on the cheek face.
  static void _faceDetail(Canvas canvas, BuccalShape s, CruColors c) {
    canvas.save();
    canvas.clipPath(s.crown);
    for (final g in s.grooves) {
      canvas.drawPath(
        smoothOpen(g),
        _blurred(c.toothShadow.withValues(alpha: 0.11), s.k * 0.3)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s.k * 0.55,
      );
    }
    if (s.ridge != null) {
      canvas.drawPath(
        smoothOpen(s.ridge!),
        _blurred(c.toothGloss.withValues(alpha: 0.75), s.k * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s.k * 0.9,
      );
    }
    canvas.restore();
  }

  /// A root: warm, rounding away at every edge, lit down its middle.
  static void _root(Canvas canvas, Path p, BuccalShape s, CruColors c, {bool back = false}) {
    final r = p.getBounds();
    final thick = s.rootThickness;
    canvas.drawPath(p, Paint()..color = back ? Color.lerp(c.toothRoot, c.rootShade, 0.45)! : c.toothRoot);
    canvas.save();
    canvas.clipPath(p);
    final neck = Offset(r.center.dx, s.upper ? r.bottom : r.top);
    final tip = Offset(r.center.dx, s.upper ? r.top : r.bottom);
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          neck,
          tip,
          [_clear(c.rootShade), c.rootShade.withValues(alpha: 0.35)],
        ),
    );
    canvas.drawPath(
      p,
      _blurred(c.rootShade.withValues(alpha: back ? 0.5 : 0.75), thick * 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick * 0.34,
    );
    if (!back) {
      for (final axis in s.canals) {
        final lit = [for (final q in axis.skip(1)) q.translate(-thick * 0.1, 0)];
        canvas.drawPath(
          smoothOpen(lit),
          _blurred(c.rootLight.withValues(alpha: 0.9), thick * 0.1)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = thick * 0.2,
        );
      }
    }
    canvas.restore();
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _line(s.k)
        ..color = c.rootShade.withValues(alpha: back ? 0.6 : 0.95),
    );
  }

  /// A titanium fixture where the root was.
  static void _implant(Canvas canvas, BuccalShape s, CruColors c) {
    final r = s.implant.getBounds();
    final metal = c.implantMetal;
    canvas.drawPath(
      s.implant,
      Paint()
        ..shader = ui.Gradient.linear(
          r.centerLeft,
          r.centerRight,
          [
            Color.lerp(metal, c.toothShadow, 0.35)!,
            Color.lerp(metal, c.toothGloss, 0.55)!,
            metal,
            Color.lerp(metal, c.toothShadow, 0.4)!,
          ],
          const [0, 0.32, 0.62, 1],
        ),
    );
    canvas.save();
    canvas.clipPath(s.implant);
    final thread = Paint()
      ..strokeWidth = math.max(0.8, s.k * 0.22)
      ..color = Color.lerp(metal, c.toothShadow, 0.45)!;
    for (final (a, b) in s.threads) {
      canvas.drawLine(a, b, thread);
    }
    canvas.restore();
    canvas.drawPath(
      s.implant,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _line(s.k)
        ..color = Color.lerp(metal, c.toothShadow, 0.5)!,
    );
  }

  /// A missing tooth: a faint dashed ghost.
  static void _ghost(Canvas canvas, List<Path> paths, CruColors c) {
    for (final p in paths) {
      canvas.drawPath(p, Paint()..color = c.inset.withValues(alpha: 0.6));
      dashPath(
        canvas,
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = c.label3.withValues(alpha: 0.55),
      );
    }
  }

  /// Canals filled (root canal treated), as tapering lines.
  static void _canals(Canvas canvas, BuccalShape s, CruColors c, Color color, {Path? clip, bool dashed = false}) {
    canvas.save();
    if (clip != null) canvas.clipPath(clip);
    for (final axis in s.canals) {
      _taper(canvas, smoothOpen(axis), color, s.k * 0.95, s.k * 0.3, dashed: dashed);
    }
    canvas.restore();
  }

  static void _taper(Canvas canvas, Path path, Color color, double from, double to, {bool dashed = false}) {
    const n = 14;
    for (final m in path.computeMetrics()) {
      for (var i = 0; i < n; i++) {
        if (dashed && i.isOdd) continue;
        final seg = m.extractPath(m.length * i / n, m.length * (i + 1) / n + 0.3);
        canvas.drawPath(
          seg,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = dashed ? StrokeCap.butt : StrokeCap.round
            ..strokeWidth = from + (to - from) * i / (n - 1)
            ..color = color,
        );
      }
    }
  }

  /// Endo view: the pulp chamber and canals, and what the endo record
  /// says about them.
  static void _pulp(Canvas canvas, BuccalShape s, ToothLook look, CruColors c) {
    final tone = look.inflamed ? c.amber : c.pulp;
    if (look.lesion) {
      for (final a in s.apexes) {
        final r = s.k * 2.6;
        canvas.drawCircle(
          a,
          r,
          Paint()
            ..shader = ui.Gradient.radial(a, r, [
              c.amber.withValues(alpha: 0.55),
              c.amber.withValues(alpha: 0.28),
              _clear(c.amber),
            ], const [0, 0.55, 1]),
        );
      }
    }
    final filled = look.canals == CanalState.obturated ||
        (look.canals == CanalState.none && look.rootCanal);
    canvas.drawPath(
      s.chamber,
      Paint()..color = filled ? c.greenText.withValues(alpha: 0.5) : tone.withValues(alpha: 0.6),
    );
    switch (look.canals) {
      case CanalState.obturated:
        _canals(canvas, s, c, c.greenText);
      case CanalState.inProgress:
        _canals(canvas, s, c, tone.withValues(alpha: 0.7));
        _canals(canvas, s, c, c.amberText, dashed: true);
      case CanalState.none:
        _canals(canvas, s, c, look.rootCanal ? c.greenText : tone.withValues(alpha: 0.7));
    }
  }

  /// A prosthetic crown: a glazed cap with its margin at the neck.
  static void _cap(Canvas canvas, Path p, Rect r, CruColors c, double k, {List<Offset>? neck}) {
    canvas.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topLeft,
          r.bottomRight,
          [
            c.restoration.withValues(alpha: 0.42),
            c.restoration.withValues(alpha: 0.62),
          ],
        ),
    );
    canvas.save();
    canvas.clipPath(p);
    final g = Rect.fromCenter(
      center: Offset(r.left + r.width * 0.34, r.top + r.height * 0.36),
      width: r.width * 0.2,
      height: r.height * 0.4,
    );
    canvas.drawOval(g, _blurred(c.toothGloss.withValues(alpha: 0.9), r.width * 0.05));
    canvas.restore();
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _line(k) * 1.2
        ..color = c.greenText.withValues(alpha: 0.75),
    );
    if (neck != null) {
      canvas.drawPath(
        smoothOpen(neck),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _line(k) * 1.8
          ..color = c.greenText,
      );
    }
  }

  /// The union of [areas], cut to [outline]; null when there are none.
  static Path? _areas(Iterable<Object?> areas, Path outline) {
    Path? out;
    for (final a in areas) {
      final p = switch (a) {
        final Rect r => Path()..addOval(r),
        final Path p => p,
        _ => null,
      };
      if (p == null) continue;
      out = out == null ? p : Path.combine(PathOperation.union, out, p);
    }
    return out == null ? null : Path.combine(PathOperation.intersect, out, outline);
  }

  /// A filling: glossy, green-tinted material with a crisp margin.
  static void _restoration(Canvas canvas, Path p, CruColors c, double k) {
    final r = p.getBounds();
    canvas.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.radial(
          r.center.translate(-r.width * 0.18, -r.height * 0.18),
          r.longestSide * 0.75,
          [
            Color.lerp(c.restoration, c.toothGloss, 0.45)!,
            c.restoration,
            Color.lerp(c.restoration, c.greenText, 0.3)!,
          ],
          const [0, 0.55, 1],
        ),
    );
    canvas.save();
    canvas.clipPath(p);
    canvas.drawOval(
      Rect.fromCenter(
        center: r.center.translate(-r.width * 0.16, -r.height * 0.16),
        width: r.width * 0.34,
        height: r.height * 0.26,
      ),
      _blurred(c.toothGloss.withValues(alpha: 0.8), r.shortestSide * 0.08),
    );
    canvas.restore();
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _line(k)
        ..color = c.greenText.withValues(alpha: 0.9),
    );
  }

  /// Decay: a dark stain fading into the enamel.
  static void _lesion(Canvas canvas, Object area, Path clip, CruColors c) {
    final r = switch (area) {
      final Rect r => r,
      final Path p => p.getBounds(),
      _ => Rect.zero,
    };
    final center = r.center;
    final radius = r.shortestSide * 0.52;
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(center, radius, [
          c.caries.withValues(alpha: 0.95),
          c.caries.withValues(alpha: 0.75),
          c.amber.withValues(alpha: 0.35),
          _clear(c.amber),
        ], const [0, 0.35, 0.7, 1]),
    );
    canvas.restore();
  }

  static void _crack(Canvas canvas, List<Offset> pts, CruColors c, double k) {
    final path = Path()..addPolygon(pts, false);
    canvas.drawPath(
      path.shift(const Offset(0.8, 0.8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..color = c.toothGloss.withValues(alpha: 0.9),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (k * 0.2).clamp(1.2, 2.2)
        ..strokeJoin = StrokeJoin.round
        ..color = c.amberText,
    );
  }

  /// Planned work: dashed Ink outlines of what will be done.
  static void _plannedBuccal(Canvas canvas, BuccalShape s, ToothLook look, CruColors c) {
    if (look.planned.isEmpty) return;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, s.k * 0.26)
      ..strokeCap = StrokeCap.round
      ..color = c.accent;
    final wash = Paint()..color = c.accentTint.withValues(alpha: 0.55);
    for (final t in look.planned.toSet()) {
      switch (t) {
        case ToothTreatment.filling:
          final area = _areas(
            (look.decay.isNotEmpty ? look.decay : {_mainSurface(s.spec)}).map(s.surfaceArea),
            s.crown,
          );
          if (area != null) {
            canvas.drawPath(area, wash);
            dashPath(canvas, area, ink, dash: 3, gap: 2.5);
          }
        case ToothTreatment.crown || ToothTreatment.bridge:
          canvas.drawPath(s.crown, wash);
          dashPath(canvas, s.crown, ink);
        case ToothTreatment.rct:
          canvas.save();
          canvas.clipPath(s.roots);
          for (final axis in s.canals) {
            dashPath(canvas, smoothOpen(axis), ink..strokeWidth = math.max(1.6, s.k * 0.4), dash: 3, gap: 2.5);
          }
          canvas.restore();
        case ToothTreatment.implant:
          canvas.drawPath(s.implant, wash);
          dashPath(canvas, s.implant, ink);
          dashPath(canvas, s.crown, ink);
        case ToothTreatment.extraction:
          final b = s.bounds.deflate(s.k * 0.6);
          ink.strokeWidth = math.max(1.6, s.k * 0.34);
          canvas.drawLine(b.topLeft, b.bottomRight, ink);
          canvas.drawLine(b.topRight, b.bottomLeft, ink);
        case ToothTreatment.scaling:
          dashPath(canvas, smoothOpen(s.neck), ink, dash: 3, gap: 2.5);
        case null:
          dashPath(canvas, s.silhouette, ink);
      }
    }
  }

  /// The surface a filling goes on when none was recorded.
  static ToothSurface _mainSurface(ToothSpec s) =>
      s.kind == ToothKind.premolar || s.kind == ToothKind.molar
          ? ToothSurface.occlusal
          : ToothSurface.buccal;

  // -------------------------------------------------------- occlusal

  /// The biting surface of one tooth.
  static void occlusal(Canvas canvas, OcclusalShape s, ToothLook look, CruColors c) {
    if (look.missing) {
      _ghost(canvas, [s.outline], c);
      if (look.implant) {
        canvas.drawCircle(s.rect.center, s.rect.shortestSide * 0.22, Paint()..color = c.implantMetal);
      }
      _plannedOcclusal(canvas, s, look, c);
      return;
    }
    final fade = look.dim || look.unerupted;
    if (fade) {
      canvas.saveLayer(
        s.rect.inflate(s.k * 4),
        Paint()..color = Color.fromRGBO(0, 0, 0, look.dim ? 0.42 : 0.45),
      );
    }
    _biting(canvas, s, c);
    if (look.capped) {
      _cap(canvas, s.outline, s.rect, c, s.k);
    } else {
      final filled = _areas(look.filled.map(s.surfaceArea), s.outline);
      if (filled != null) _restoration(canvas, filled, c, s.k);
    }
    for (final surface in look.decay) {
      if (surface == ToothSurface.occlusal && !s.front) {
        _fissureDecay(canvas, s, c);
      } else {
        final a = s.surfaceArea(surface);
        if (a != null) _lesion(canvas, a, s.outline, c);
      }
    }
    if (look.fractured) _crack(canvas, s.crack, c, s.k);
    if (look.rootCanal && look.pulp) {
      canvas.drawCircle(
        s.rect.center,
        s.rect.shortestSide * 0.16,
        Paint()..color = c.greenText.withValues(alpha: 0.6),
      );
    }
    if (look.impacted) {
      dashPath(
        canvas,
        s.outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = c.amberText,
      );
    }
    if (fade) canvas.restore();
    _plannedOcclusal(canvas, s, look, c);
  }

  /// Enamel seen from above: a dome with lit cusps, dark fissures and
  /// pits; front teeth show their biting edge and the hollow behind it.
  static void _biting(Canvas canvas, OcclusalShape s, CruColors c) {
    final p = s.outline;
    final r = s.rect;
    final k = s.k;
    canvas.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.radial(
          r.center.translate(-r.width * 0.05, -r.height * 0.05),
          r.longestSide * 0.6,
          [c.enamelMid, c.enamel, c.enamelMid, c.enamelShade],
          const [0, 0.42, 0.8, 1],
        ),
    );
    canvas.save();
    canvas.clipPath(p);
    // Cusps: bumps lit from the upper left.
    for (final (tip, rad) in s.cusps) {
      canvas.drawCircle(
        tip.translate(rad * 0.3, rad * 0.34),
        rad * 1.05,
        Paint()
          ..shader = ui.Gradient.radial(tip.translate(rad * 0.3, rad * 0.34), rad * 1.05, [
            c.toothShadow.withValues(alpha: 0.24),
            _clear(c.toothShadow),
          ]),
      );
      canvas.drawCircle(
        tip.translate(-rad * 0.14, -rad * 0.16),
        rad * 1.1,
        Paint()
          ..shader = ui.Gradient.radial(tip.translate(-rad * 0.14, -rad * 0.16), rad * 1.1, [
            c.toothGloss.withValues(alpha: 0.95),
            c.toothGloss.withValues(alpha: 0.45),
            _clear(c.toothGloss),
          ], const [0, 0.45, 1]),
      );
    }
    for (final ridge in s.ridges) {
      canvas.drawPath(
        smoothOpen(ridge),
        _blurred(c.toothGloss.withValues(alpha: 0.8), k * 0.3)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = k * 0.7,
      );
    }
    // Front teeth: the hollow behind the edge, the edge, the bulge.
    if (s.incisal != null) {
      final fossa = Offset(r.center.dx, (s.incisal!.first.dy + s.cingulum!.dy) / 2);
      final fr = r.width * 0.36;
      canvas.drawCircle(
        fossa,
        fr,
        Paint()
          ..shader = ui.Gradient.radial(fossa, fr, [
            c.toothShadow.withValues(alpha: 0.14),
            _clear(c.toothShadow),
          ]),
      );
      final cr = r.width * 0.26;
      canvas.drawCircle(
        s.cingulum!,
        cr,
        Paint()
          ..shader = ui.Gradient.radial(s.cingulum!, cr, [
            c.toothGloss.withValues(alpha: 0.85),
            _clear(c.toothGloss),
          ]),
      );
      final edge = smoothOpen(s.incisal!);
      canvas.drawPath(
        edge.shift(Offset(0, s.upper ? k * 0.35 : -k * 0.35)),
        _blurred(c.toothShadow.withValues(alpha: 0.22), k * 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = k * 0.5,
      );
      canvas.drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1, k * 0.55)
          ..color = c.toothGloss.withValues(alpha: 0.95),
      );
    }
    // Fissures: a soft valley, a crisp groove and a lit lip.
    for (final g in s.grooves) {
      final path = smoothOpen(g);
      canvas.drawPath(
        path,
        _blurred(c.fissure.withValues(alpha: 0.2), k * 0.4)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = k * 0.8,
      );
      canvas.drawPath(
        path.shift(Offset(-k * 0.1, -k * 0.1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(0.8, k * 0.2)
          ..color = c.toothGloss.withValues(alpha: 0.5),
      );
      canvas.drawPath(
        path,
        _blurred(c.fissure.withValues(alpha: 0.6), math.min(k * 0.06, 0.6))
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = (k * 0.16).clamp(0.7, 2.2),
      );
    }
    for (final pit in s.pits) {
      canvas.drawCircle(pit, math.max(0.8, k * 0.24), _blurred(c.fissure.withValues(alpha: 0.5), k * 0.12));
    }
    // Rounding away at the outline.
    canvas.drawPath(
      p,
      _blurred(c.toothShadow.withValues(alpha: 0.2), r.shortestSide * 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.shortestSide * 0.2,
    );
    canvas.restore();
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _line(k)
        ..color = c.enamelEdge.withValues(alpha: 0.8),
    );
  }

  /// Decay in the fissures of a back tooth.
  static void _fissureDecay(Canvas canvas, OcclusalShape s, CruColors c) {
    canvas.save();
    canvas.clipPath(s.outline);
    for (final g in s.grooves) {
      canvas.drawPath(
        smoothOpen(g),
        _blurred(c.caries.withValues(alpha: 0.7), math.min(s.k * 0.25, 1.6))
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.min(s.k * 0.6, 4.5),
      );
    }
    final at = s.pits.isEmpty ? s.rect.center : s.pits[s.pits.length ~/ 2];
    final r = s.rect.shortestSide * 0.18;
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..shader = ui.Gradient.radial(at, r, [
          c.caries.withValues(alpha: 0.95),
          c.amber.withValues(alpha: 0.35),
          _clear(c.amber),
        ], const [0, 0.55, 1]),
    );
    canvas.restore();
  }

  static void _plannedOcclusal(Canvas canvas, OcclusalShape s, ToothLook look, CruColors c) {
    if (look.planned.isEmpty) return;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, s.k * 0.26)
      ..strokeCap = StrokeCap.round
      ..color = c.accent;
    final wash = Paint()..color = c.accentTint.withValues(alpha: 0.55);
    for (final t in look.planned.toSet()) {
      switch (t) {
        case ToothTreatment.filling:
          final area = _areas(
            (look.decay.isNotEmpty ? look.decay : {_mainSurface(s.spec)}).map(s.surfaceArea),
            s.outline,
          );
          if (area != null) {
            canvas.drawPath(area, wash);
            dashPath(canvas, area, ink, dash: 3, gap: 2.5);
          }
        case ToothTreatment.crown ||
              ToothTreatment.bridge ||
              ToothTreatment.implant ||
              null:
          canvas.drawPath(s.outline, wash);
          dashPath(canvas, s.outline, ink);
        case ToothTreatment.extraction:
          final b = s.rect.deflate(s.k * 0.5);
          canvas.drawLine(b.topLeft, b.bottomRight, ink);
          canvas.drawLine(b.topRight, b.bottomLeft, ink);
        case ToothTreatment.rct:
          canvas.drawCircle(s.rect.center, s.rect.shortestSide * 0.16, wash);
          dashPath(
            canvas,
            Path()..addOval(Rect.fromCircle(center: s.rect.center, radius: s.rect.shortestSide * 0.16)),
            ink,
            dash: 2.5,
            gap: 2,
          );
        case ToothTreatment.scaling:
          break;
      }
    }
  }

  // ------------------------------------------------------------ perio

  /// Pockets on the cheek side from perio readings at the distal, middle
  /// and mesial sites (recession moves the margin rootwards). Returns the
  /// gum margin with a papilla at each side, left to right, so it can be
  /// joined up with the neighbours, and the sites that bled.
  static ({List<Offset> margin, List<Offset> bleeding}) pockets(
    Canvas canvas,
    BuccalShape s,
    CruColors c, {
    required List<int?> pd,
    required List<int?> rec,
    required List<bool> bop,
    int? furcation,
  }) {
    final margin = <Offset>[];
    final pocket = <Offset>[];
    for (var i = 0; i < 3; i++) {
      final m = s.site(i).translate(0, s.rootward * (rec[i] ?? 0));
      margin.add(m);
      pocket.add(m.translate(0, s.rootward * (pd[i] ?? 0)));
    }
    final deep = pd.any((d) => (d ?? 0) >= 4);
    canvas.drawPath(
      smoothClosed([...margin, ...pocket.reversed]),
      Paint()
        ..color = deep ? c.amber.withValues(alpha: 0.42) : c.gum.withValues(alpha: 0.32),
    );
    canvas.drawPath(
      smoothOpen(pocket),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = deep
            ? c.amberText.withValues(alpha: 0.8)
            : c.gumShade.withValues(alpha: 0.6),
    );
    final f = s.furcation;
    if (f != null && (furcation ?? 0) > 0) {
      final t = Path()
        ..moveTo(f.dx, f.dy)
        ..lineTo(f.dx - 4, f.dy + s.rootward * 1.4)
        ..lineTo(f.dx + 4, f.dy + s.rootward * 1.4)
        ..close();
      canvas.drawPath(t, Paint()..color = furcation! >= 2 ? c.amberText : c.surface);
      canvas.drawPath(
        t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..color = c.amberText,
      );
    }
    final papilla = s.rootward * -1.1;
    final sorted = [...margin]..sort((a, b) => a.dx.compareTo(b.dx));
    return (
      margin: [
        Offset(s.crownRect.left + s.k * 0.2, sorted.first.dy + papilla),
        ...sorted,
        Offset(s.crownRect.right - s.k * 0.2, sorted.last.dy + papilla),
      ],
      bleeding: [
        for (var i = 0; i < 3; i++)
          if (bop[i]) margin[i],
      ],
    );
  }

  /// The gum margin through [points].
  static void gumLine(Canvas canvas, List<Offset> points, CruColors c) {
    if (points.length < 2) return;
    canvas.drawPath(
      smoothOpen(points),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = c.gumShade,
    );
  }

  /// Bleeding on probing.
  static void bleeding(Canvas canvas, Iterable<Offset> points, CruColors c) {
    for (final p in points) {
      canvas.drawCircle(p, 3.2, Paint()..color = c.surface);
      canvas.drawCircle(p, 2.4, Paint()..color = c.amber);
    }
  }

  // ------------------------------------------------------------ rings

  /// Hover and selection: a soft Ink glow around the tooth.
  static void ring(Canvas canvas, Path outline, CruColors c, {required bool selected, required double k}) {
    if (selected) {
      canvas.drawPath(
        outline,
        _blurred(c.accent.withValues(alpha: 0.35), 3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = selected ? 2 : 1.5
        ..color = selected ? c.accent : c.accent.withValues(alpha: 0.45),
    );
  }
}
