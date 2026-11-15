/// Real tooth dimensions (mm) for the hand-drawn vector tooth library.
///
/// Crown length, root length, mesio-distal (MD) and bucco-lingual (BL) widths
/// follow the standard table in Wheeler's Dental Anatomy (permanent teeth) and
/// the usual primary-tooth table. The depth of curvature of the cervical line
/// (how far the CEJ rises toward the biting edge on the mesial and distal
/// side) is the textbook figure per tooth, recalled from the same source; the
/// crown/root colour boundary of every tooth is drawn from it, so no two
/// types share one CEJ shape.
library;

enum ToothKind { central, lateral, canine, pm1, pm2, m1, m2, m3 }

/// Dimensions and root layout of one tooth type.
class ToothDims {
  const ToothDims({
    required this.kind,
    required this.upper,
    required this.crownH,
    required this.crownW,
    required this.cervW,
    required this.rootLen,
    required this.bl,
    required this.blCerv,
    required this.cejMesial,
    required this.cejDistal,
    this.cejSharp = 1.7,
    this.cejDip = 0,
    this.roots = 1,
    this.trunk = 0,
    this.spread = 0,
    this.curve = 0,
    this.fused = false,
    this.primary = false,
  });

  final ToothKind kind;
  final bool upper;
  final bool primary;

  /// Crown height at the middle of the face (biting edge to CEJ), mm.
  final double crownH;

  /// Crown width mesio-distal at the contact points, mm.
  final double crownW;

  /// Width of the crown at the CEJ, mm.
  final double cervW;

  /// Root length from the middle of the CEJ to the apex, mm.
  final double rootLen;

  /// Crown width bucco-lingual (occlusal view), mm.
  final double bl;

  /// BL width at the neck, mm.
  final double blCerv;

  /// How far the CEJ rises toward the biting edge at the mesial / distal end.
  final double cejMesial;
  final double cejDistal;

  /// Exponent of the CEJ arch: higher is flatter in the middle and steeper at
  /// the ends.
  final double cejSharp;

  /// Extra upward pull of the CEJ at the ends relative to the middle (molars
  /// point toward the furcation).
  final double cejDip;

  /// Roots visible from the cheek (1, 2, or 3 with the palatal root peeking).
  final int roots;

  /// Root trunk depth (CEJ to furcation), molars.
  final double trunk;

  /// How far the root tips splay outward, mm.
  final double spread;

  /// Distal curvature of the apex, mm.
  final double curve;

  /// Roots converge into one cone (third molars).
  final bool fused;

  ToothDims copyWith({double? crownW, double? crownH}) => ToothDims(
        kind: kind,
        upper: upper,
        crownH: crownH ?? this.crownH,
        crownW: crownW ?? this.crownW,
        cervW: cervW,
        rootLen: rootLen,
        bl: bl,
        blCerv: blCerv,
        cejMesial: cejMesial,
        cejDistal: cejDistal,
        cejSharp: cejSharp,
        cejDip: cejDip,
        roots: roots,
        trunk: trunk,
        spread: spread,
        curve: curve,
        fused: fused,
        primary: primary,
      );

  /// Looks the type up from a two-digit FDI number (11-48, 51-85).
  static ToothDims of(int fdi) {
    final q = fdi ~/ 10;
    final n = fdi % 10;
    final primary = q >= 5;
    final quadrant = primary ? q - 4 : q;
    final upper = quadrant <= 2;
    final ToothKind kind;
    if (primary) {
      kind = switch (n) {
        1 => ToothKind.central,
        2 => ToothKind.lateral,
        3 => ToothKind.canine,
        4 => ToothKind.m1,
        _ => ToothKind.m2,
      };
      return (upper ? _milkUpper : _milkLower)[kind]!;
    }
    kind = ToothKind.values[(n - 1).clamp(0, 7)];
    return (upper ? _upper : _lower)[kind]!;
  }

  /// FDI quadrant 2, 3, 6 and 7 are drawn mirrored.
  static bool isLeft(int fdi) {
    final q = fdi ~/ 10;
    return q == 2 || q == 3 || q == 6 || q == 7;
  }

  static const Map<ToothKind, ToothDims> _upper = {
    ToothKind.central: ToothDims(
      kind: ToothKind.central, upper: true,
      crownH: 10.5, crownW: 8.5, cervW: 7.0, rootLen: 13.0, bl: 7.0, blCerv: 6.0,
      cejMesial: 3.5, cejDistal: 2.5, cejSharp: 1.8, curve: 0.5,
    ),
    ToothKind.lateral: ToothDims(
      kind: ToothKind.lateral, upper: true,
      crownH: 9.0, crownW: 6.5, cervW: 5.0, rootLen: 13.0, bl: 6.0, blCerv: 5.0,
      cejMesial: 3.0, cejDistal: 2.0, cejSharp: 1.8, curve: 1.2,
    ),
    ToothKind.canine: ToothDims(
      kind: ToothKind.canine, upper: true,
      crownH: 10.5, crownW: 7.5, cervW: 5.6, rootLen: 16.5, bl: 8.0, blCerv: 7.0,
      cejMesial: 2.5, cejDistal: 1.5, cejSharp: 1.6, curve: 0.8,
    ),
    ToothKind.pm1: ToothDims(
      kind: ToothKind.pm1, upper: true,
      crownH: 9.0, crownW: 7.0, cervW: 5.2, rootLen: 13.5, bl: 9.0, blCerv: 8.0,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.5, curve: 0.5,
    ),
    ToothKind.pm2: ToothDims(
      kind: ToothKind.pm2, upper: true,
      crownH: 9.0, crownW: 7.0, cervW: 5.2, rootLen: 13.5, bl: 9.0, blCerv: 8.0,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.5, curve: 0.7,
    ),
    ToothKind.m1: ToothDims(
      kind: ToothKind.m1, upper: true,
      crownH: 7.5, crownW: 10.0, cervW: 8.0, rootLen: 12.5, bl: 11.0, blCerv: 10.0,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.5,
      roots: 3, trunk: 4.0, spread: 1.7, curve: 0.6,
    ),
    ToothKind.m2: ToothDims(
      kind: ToothKind.m2, upper: true,
      crownH: 7.0, crownW: 9.0, cervW: 7.0, rootLen: 11.5, bl: 11.0, blCerv: 10.0,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.4,
      roots: 3, trunk: 4.5, spread: 1.1, curve: 0.9,
    ),
    ToothKind.m3: ToothDims(
      kind: ToothKind.m3, upper: true,
      crownH: 6.5, crownW: 8.5, cervW: 6.5, rootLen: 9.5, bl: 10.0, blCerv: 9.5,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.3,
      roots: 1, trunk: 0, curve: 0.8, fused: true,
    ),
  };

  static const Map<ToothKind, ToothDims> _lower = {
    ToothKind.central: ToothDims(
      kind: ToothKind.central, upper: false,
      crownH: 9.0, crownW: 5.0, cervW: 3.5, rootLen: 12.5, bl: 6.0, blCerv: 5.3,
      cejMesial: 3.0, cejDistal: 2.0, cejSharp: 1.8, curve: 0.3,
    ),
    ToothKind.lateral: ToothDims(
      kind: ToothKind.lateral, upper: false,
      crownH: 9.5, crownW: 5.5, cervW: 4.0, rootLen: 14.0, bl: 6.5, blCerv: 5.8,
      cejMesial: 3.0, cejDistal: 2.0, cejSharp: 1.8, curve: 0.6,
    ),
    ToothKind.canine: ToothDims(
      kind: ToothKind.canine, upper: false,
      crownH: 11.0, crownW: 7.0, cervW: 5.6, rootLen: 15.5, bl: 7.5, blCerv: 7.0,
      cejMesial: 2.5, cejDistal: 1.0, cejSharp: 1.6, curve: 0.9,
    ),
    ToothKind.pm1: ToothDims(
      kind: ToothKind.pm1, upper: false,
      crownH: 9.0, crownW: 7.0, cervW: 5.2, rootLen: 13.5, bl: 7.5, blCerv: 6.5,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.5, curve: 0.5,
    ),
    ToothKind.pm2: ToothDims(
      kind: ToothKind.pm2, upper: false,
      crownH: 8.8, crownW: 7.0, cervW: 5.2, rootLen: 14.0, bl: 8.0, blCerv: 7.0,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.5, curve: 0.5,
    ),
    ToothKind.m1: ToothDims(
      kind: ToothKind.m1, upper: false,
      crownH: 7.5, crownW: 11.0, cervW: 9.0, rootLen: 14.0, bl: 10.5, blCerv: 9.0,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.7,
      roots: 2, trunk: 3.5, spread: 0.9, curve: 1.0,
    ),
    ToothKind.m2: ToothDims(
      kind: ToothKind.m2, upper: false,
      crownH: 7.0, crownW: 10.5, cervW: 8.0, rootLen: 13.0, bl: 10.0, blCerv: 9.0,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.6,
      roots: 2, trunk: 4.0, spread: 0.5, curve: 1.1,
    ),
    ToothKind.m3: ToothDims(
      kind: ToothKind.m3, upper: false,
      crownH: 7.0, crownW: 10.0, cervW: 7.5, rootLen: 9.5, bl: 9.5, blCerv: 8.5,
      cejMesial: 1.0, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.4,
      roots: 1, trunk: 0, curve: 0.8, fused: true,
    ),
  };

  // Primary teeth: bulbous crowns, strong cervical constriction, long thin
  // roots on the front teeth, widely splayed roots on the molars.
  static const Map<ToothKind, ToothDims> _milkUpper = {
    ToothKind.central: ToothDims(
      kind: ToothKind.central, upper: true, primary: true,
      crownH: 6.0, crownW: 6.5, cervW: 4.5, rootLen: 10.0, bl: 5.0, blCerv: 4.2,
      cejMesial: 2.0, cejDistal: 1.5, cejSharp: 1.8, curve: 0.3,
    ),
    ToothKind.lateral: ToothDims(
      kind: ToothKind.lateral, upper: true, primary: true,
      crownH: 5.6, crownW: 5.1, cervW: 3.7, rootLen: 10.0, bl: 4.5, blCerv: 3.8,
      cejMesial: 2.0, cejDistal: 1.5, cejSharp: 1.8, curve: 0.6,
    ),
    ToothKind.canine: ToothDims(
      kind: ToothKind.canine, upper: true, primary: true,
      crownH: 6.5, crownW: 7.0, cervW: 5.0, rootLen: 13.0, bl: 7.0, blCerv: 6.0,
      cejMesial: 1.5, cejDistal: 1.0, cejSharp: 1.6, curve: 0.6,
    ),
    ToothKind.m1: ToothDims(
      kind: ToothKind.m1, upper: true, primary: true,
      crownH: 5.1, crownW: 7.0, cervW: 5.2, rootLen: 10.0, bl: 8.5, blCerv: 7.2,
      cejMesial: 0.6, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.3,
      roots: 3, trunk: 2.6, spread: 2.0, curve: 0.3,
    ),
    ToothKind.m2: ToothDims(
      kind: ToothKind.m2, upper: true, primary: true,
      crownH: 5.7, crownW: 8.5, cervW: 6.4, rootLen: 11.0, bl: 10.0, blCerv: 8.5,
      cejMesial: 0.6, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.3,
      roots: 3, trunk: 3.0, spread: 2.4, curve: 0.3,
    ),
  };

  static const Map<ToothKind, ToothDims> _milkLower = {
    ToothKind.central: ToothDims(
      kind: ToothKind.central, upper: false, primary: true,
      crownH: 5.0, crownW: 4.2, cervW: 3.0, rootLen: 9.0, bl: 3.6, blCerv: 3.2,
      cejMesial: 2.0, cejDistal: 1.5, cejSharp: 1.8, curve: 0.2,
    ),
    ToothKind.lateral: ToothDims(
      kind: ToothKind.lateral, upper: false, primary: true,
      crownH: 5.2, crownW: 4.1, cervW: 3.4, rootLen: 10.0, bl: 4.0, blCerv: 3.5,
      cejMesial: 2.0, cejDistal: 1.5, cejSharp: 1.8, curve: 0.4,
    ),
    ToothKind.canine: ToothDims(
      kind: ToothKind.canine, upper: false, primary: true,
      crownH: 6.0, crownW: 5.0, cervW: 3.7, rootLen: 12.0, bl: 5.0, blCerv: 4.4,
      cejMesial: 1.5, cejDistal: 1.0, cejSharp: 1.6, curve: 0.5,
    ),
    ToothKind.m1: ToothDims(
      kind: ToothKind.m1, upper: false, primary: true,
      crownH: 6.0, crownW: 7.7, cervW: 6.5, rootLen: 9.8, bl: 7.0, blCerv: 6.0,
      cejMesial: 0.4, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.3,
      roots: 2, trunk: 2.4, spread: 1.4, curve: 0.5,
    ),
    ToothKind.m2: ToothDims(
      kind: ToothKind.m2, upper: false, primary: true,
      crownH: 5.5, crownW: 9.9, cervW: 7.2, rootLen: 11.3, bl: 8.7, blCerv: 7.5,
      cejMesial: 0.4, cejDistal: 0.0, cejSharp: 1.6, cejDip: 0.3,
      roots: 2, trunk: 2.8, spread: 1.8, curve: 0.5,
    ),
  };
}
