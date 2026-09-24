// Cephalometric landmarks, the standard analyses with their textbook norms
// (mean ± 1 SD, adult values), and the geometry that turns placed
// landmarks into values. Everything works in a "face frame": the image is
// mirrored when the profile faces left, so anterior is always +x and
// inferior +y.

import 'dart:math' as math;
import 'dart:ui' show Offset;

enum CephGroup {
  cranial('Cranial base'),
  maxilla('Maxilla'),
  teeth('Teeth'),
  mandible('Mandible'),
  soft('Soft tissue');

  const CephGroup(this.label);
  final String label;
}

/// One landmark: its short name (the key it's saved under), full name and
/// where to put it.
class CephLandmark {
  const CephLandmark(this.id, this.name, this.hint, this.group);

  final String id;
  final String name;
  final String hint;
  final CephGroup group;
}

/// In the order the guided placement asks for them.
const cephLandmarks = <CephLandmark>[
  CephLandmark('S', 'Sella', 'Centre of the sella turcica', CephGroup.cranial),
  CephLandmark('N', 'Nasion', 'Most anterior point of the frontonasal suture', CephGroup.cranial),
  CephLandmark('Or', 'Orbitale', 'Lowest point on the inferior margin of the orbit', CephGroup.cranial),
  CephLandmark('Po', 'Porion', 'Top of the external auditory meatus', CephGroup.cranial),
  CephLandmark('Ba', 'Basion', 'Lowest, most anterior point of the foramen magnum', CephGroup.cranial),
  CephLandmark('Ar', 'Articulare', 'Where the back of the ramus crosses the cranial base',
      CephGroup.cranial),
  CephLandmark('Co', 'Condylion', 'Most superior-posterior point of the condyle', CephGroup.cranial),
  CephLandmark('Pt', 'Pterygoid point',
      'Top-back of the pterygomaxillary fissure (11 o\'clock)', CephGroup.cranial),
  CephLandmark('ANS', 'Anterior nasal spine', 'Tip of the anterior nasal spine', CephGroup.maxilla),
  CephLandmark('PNS', 'Posterior nasal spine', 'Tip of the posterior nasal spine', CephGroup.maxilla),
  CephLandmark('A', 'Point A', 'Deepest point of the anterior maxillary concavity',
      CephGroup.maxilla),
  CephLandmark('U1T', 'Upper incisor tip', 'Incisal edge of the most prominent upper incisor',
      CephGroup.teeth),
  CephLandmark('U1A', 'Upper incisor apex', 'Root apex of the same upper incisor', CephGroup.teeth),
  CephLandmark('L1T', 'Lower incisor tip', 'Incisal edge of the most prominent lower incisor',
      CephGroup.teeth),
  CephLandmark('L1A', 'Lower incisor apex', 'Root apex of the same lower incisor', CephGroup.teeth),
  CephLandmark('Mo', 'Molar occlusion', 'Where the first molars\' cusps meet (occlusal plane)',
      CephGroup.teeth),
  CephLandmark('B', 'Point B', 'Deepest point of the anterior mandibular concavity',
      CephGroup.mandible),
  CephLandmark('Pog', 'Pogonion', 'Most anterior point of the bony chin', CephGroup.mandible),
  CephLandmark('Gn', 'Gnathion', 'Midway between pogonion and menton', CephGroup.mandible),
  CephLandmark('Me', 'Menton', 'Lowest point of the symphysis', CephGroup.mandible),
  CephLandmark('Go', 'Gonion', 'Most posterior-inferior point of the mandibular angle',
      CephGroup.mandible),
  CephLandmark('Prn', 'Pronasale', 'Tip of the nose', CephGroup.soft),
  CephLandmark('Cm', 'Columella', 'Most anterior point of the columella', CephGroup.soft),
  CephLandmark('Sn', 'Subnasale', 'Where the columella meets the upper lip', CephGroup.soft),
  CephLandmark('Ls', 'Labrale superius', 'Most anterior point of the upper lip', CephGroup.soft),
  CephLandmark('Li', 'Labrale inferius', 'Most anterior point of the lower lip', CephGroup.soft),
  CephLandmark("Pog'", 'Soft-tissue pogonion', 'Most anterior point of the soft-tissue chin',
      CephGroup.soft),
];

CephLandmark? cephLandmark(String id) {
  for (final l in cephLandmarks) {
    if (l.id == id) return l;
  }
  return null;
}

// ───────────────────────────── Geometry ─────────────────────────────

double _deg(double rad) => rad * 180 / math.pi;
double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// Placed landmarks in the face frame, with the helpers the analyses use.
class CephGeometry {
  CephGeometry(Map<String, Offset> points, this.mmPerPx) : _p = _faceFrame(points);

  final Map<String, Offset> _p;

  /// Null when the image isn't calibrated: millimetre values need it.
  final double? mmPerPx;

  Offset operator [](String id) => _p[id]!;

  List<String> missing(List<String> ids) => [for (final id in ids) if (!_p.containsKey(id)) id];

  /// The front of the occlusal plane: between the incisal tips.
  Offset get incisal => (this['U1T'] + this['L1T']) / 2;

  /// Down along the Nasion perpendicular (at right angles to FH).
  Offset get down => _perpDown(this['Po'], this['Or']);

  double? mm(double px) => mmPerPx == null ? null : px * mmPerPx!;

  /// The angle between two directions, 0–180°.
  static double between(Offset a, Offset b) => _deg(math.atan2(_cross(a, b).abs(), _dot(a, b)));

  /// How far [b] is turned from [a], in degrees; positive when it turns
  /// downwards (clockwise on screen, where y points down).
  static double turn(Offset a, Offset b) => _deg(math.atan2(_cross(a, b), _dot(a, b)));

  /// How far the top of line [v] leans forward of line [ref], in degrees.
  static double lean(Offset ref, Offset v) {
    final r = ref.dy > 0 ? -ref : ref;
    final u = v.dy > 0 ? -v : v;
    return turn(r, u);
  }

  /// Angle at [vertex] between [a] and [b].
  double angleAt(String a, String vertex, String b) =>
      between(this[a] - this[vertex], this[b] - this[vertex]);

  /// How far [p] is in front of the line through [l1] and [l2], in pixels
  /// (negative behind it).
  static double ahead(Offset p, Offset l1, Offset l2) {
    var d = l2 - l1;
    if (d.dy < 0) d = -d;
    final len = d.distance;
    if (len == 0) return 0;
    return -_cross(d, p - l1) / len;
  }

  static Map<String, Offset> _faceFrame(Map<String, Offset> p) {
    if (!_facesLeft(p)) return Map.of(p);
    return {for (final e in p.entries) e.key: Offset(-e.value.dx, e.value.dy)};
  }

  /// The profile faces left when Nasion is left of Sella (or Orbitale
  /// left of Porion, or Menton left of Gonion).
  static bool _facesLeft(Map<String, Offset> p) {
    for (final (back, front) in const [('S', 'N'), ('Po', 'Or'), ('Go', 'Me'), ('PNS', 'ANS')]) {
      final a = p[back], b = p[front];
      if (a != null && b != null) return b.dx < a.dx;
    }
    return false;
  }
}

/// Perpendicular to the line [po]→[or], pointing down (in image space when
/// used for drawing; the sign doesn't matter for a line).
Offset _perpDown(Offset po, Offset or) {
  final f = or - po;
  final len = f.distance;
  if (len == 0) return const Offset(0, 1);
  final u = f / len;
  final d = Offset(-u.dy, u.dx);
  return d.dy < 0 ? -d : d;
}

// ───────────────────────────── Analyses ─────────────────────────────

enum CephUnit {
  deg('°'),
  mm(' mm');

  const CephUnit(this.suffix);
  final String suffix;
}

/// One value of an analysis and its norm.
class CephMeasure {
  const CephMeasure({
    required this.key,
    required this.name,
    required this.detail,
    required this.unit,
    required this.needs,
    required this.compute,
    this.mean,
    this.sd,
  });

  /// Stable id within the analysis (saved and used in report row ids).
  final String key;
  final String name;
  final String detail;
  final CephUnit unit;
  final List<String> needs;

  /// Null when the value can't be worked out (millimetres without a scale).
  final double? Function(CephGeometry g) compute;

  /// Norm (adult mean ± 1 SD); null for values that depend on face size.
  final double? mean;
  final double? sd;

  /// "82 ± 2"; empty when there is no norm.
  String get normText => mean == null ? '' : '${_num(mean!)} ± ${_num(sd!)}';
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class CephAnalysis {
  const CephAnalysis({
    required this.key,
    required this.name,
    required this.detail,
    required this.measures,
  });

  final String key;
  final String name;
  final String detail;
  final List<CephMeasure> measures;
}

/// A worked-out value.
class CephValue {
  const CephValue(this.measure, this.value, this.missing, {this.needsScale = false});

  final CephMeasure measure;
  final double? value;

  /// Landmarks still to place for this value.
  final List<String> missing;

  /// Millimetres, but the image has no scale yet.
  final bool needsScale;

  /// How many SDs from the mean; null without a value or norm.
  double? get deviation {
    final v = value, m = measure.mean, sd = measure.sd;
    if (v == null || m == null || sd == null || sd == 0) return null;
    return (v - m) / sd;
  }

  /// Outside 1 SD (shown in amber).
  bool get outside => (deviation?.abs() ?? 0) > 1;

  /// "83.1°", "4.2 mm".
  String get text => value == null ? '' : '${value!.toStringAsFixed(1)}${measure.unit.suffix}';
}

List<CephValue> cephValues(CephAnalysis a, Map<String, Offset> points, double? mmPerPx) {
  final g = CephGeometry(points, mmPerPx);
  return [
    for (final m in a.measures)
      if (g.missing(m.needs) case final missing when missing.isNotEmpty)
        CephValue(m, null, missing)
      else if (m.compute(g) case final v?)
        CephValue(m, v, const [])
      else
        CephValue(m, null, const [], needsScale: m.unit == CephUnit.mm),
  ];
}

// Values shared by several analyses.

double _sna(CephGeometry g) => g.angleAt('S', 'N', 'A');
double _snb(CephGeometry g) => g.angleAt('S', 'N', 'B');
double _fma(CephGeometry g) => CephGeometry.turn(g['Or'] - g['Po'], g['Me'] - g['Go']);
double _impa(CephGeometry g) => CephGeometry.between(g['L1T'] - g['L1A'], g['Go'] - g['Me']);
double _interincisal(CephGeometry g) =>
    CephGeometry.between(g['U1A'] - g['U1T'], g['L1A'] - g['L1T']);
double _facialAngle(CephGeometry g) => CephGeometry.between(g['Po'] - g['Or'], g['Pog'] - g['N']);
double _facialAxis(CephGeometry g) =>
    180 - CephGeometry.between(g['N'] - g['Ba'], g['Gn'] - g['Pt']);
double? _l1APog(CephGeometry g) => g.mm(CephGeometry.ahead(g['L1T'], g['A'], g['Pog']));

const _fh = ['Po', 'Or'];
const _mp = ['Go', 'Me'];
const _u1 = ['U1T', 'U1A'];
const _l1 = ['L1T', 'L1A'];

CephMeasure _mandibularPlane(String key, double mean, double sd) => CephMeasure(
      key: key,
      name: 'FH – Mandibular plane',
      detail: 'Frankfort horizontal to Go–Me',
      unit: CephUnit.deg,
      mean: mean,
      sd: sd,
      needs: [..._fh, ..._mp],
      compute: _fma,
    );

CephMeasure _interincisalAngle(double mean, double sd) => CephMeasure(
      key: 'II',
      name: 'Interincisal angle',
      detail: 'Upper to lower incisor axis',
      unit: CephUnit.deg,
      mean: mean,
      sd: sd,
      needs: [..._u1, ..._l1],
      compute: _interincisal,
    );

const _facialAxisNeeds = ['Ba', 'N', 'Pt', 'Gn'];

/// Steiner, Downs, Tweed, McNamara and a Ricketts subset. Norms are the
/// usual textbook adult values (mean ± 1 SD).
final List<CephAnalysis> cephAnalyses = [
  CephAnalysis(
    key: 'steiner',
    name: 'Steiner',
    detail: 'Jaws and incisors against the cranial base (SN)',
    measures: [
      const CephMeasure(
        key: 'SNA',
        name: 'SNA',
        detail: 'Maxilla to cranial base',
        unit: CephUnit.deg,
        mean: 82,
        sd: 2,
        needs: ['S', 'N', 'A'],
        compute: _sna,
      ),
      const CephMeasure(
        key: 'SNB',
        name: 'SNB',
        detail: 'Mandible to cranial base',
        unit: CephUnit.deg,
        mean: 80,
        sd: 2,
        needs: ['S', 'N', 'B'],
        compute: _snb,
      ),
      CephMeasure(
        key: 'ANB',
        name: 'ANB',
        detail: 'Maxilla to mandible',
        unit: CephUnit.deg,
        mean: 2,
        sd: 2,
        needs: const ['S', 'N', 'A', 'B'],
        compute: (g) => _sna(g) - _snb(g),
      ),
      CephMeasure(
        key: 'SN_GoGn',
        name: 'SN – GoGn',
        detail: 'Mandibular plane to SN',
        unit: CephUnit.deg,
        mean: 32,
        sd: 5,
        needs: const ['S', 'N', 'Go', 'Gn'],
        compute: (g) => CephGeometry.turn(g['N'] - g['S'], g['Gn'] - g['Go']),
      ),
      CephMeasure(
        key: 'SN_OP',
        name: 'SN – Occlusal plane',
        detail: 'Occlusal plane to SN',
        unit: CephUnit.deg,
        mean: 14,
        sd: 3,
        needs: const ['S', 'N', 'U1T', 'L1T', 'Mo'],
        compute: (g) => CephGeometry.turn(g['N'] - g['S'], g.incisal - g['Mo']),
      ),
      CephMeasure(
        key: 'U1_NA_deg',
        name: 'U1 – NA',
        detail: 'Upper incisor inclination to NA',
        unit: CephUnit.deg,
        mean: 22,
        sd: 5,
        needs: const ['N', 'A', ..._u1],
        compute: (g) => -CephGeometry.lean(g['N'] - g['A'], g['U1A'] - g['U1T']),
      ),
      CephMeasure(
        key: 'U1_NA_mm',
        name: 'U1 – NA',
        detail: 'Upper incisor ahead of NA',
        unit: CephUnit.mm,
        mean: 4,
        sd: 2,
        needs: const ['N', 'A', 'U1T'],
        compute: (g) => g.mm(CephGeometry.ahead(g['U1T'], g['N'], g['A'])),
      ),
      CephMeasure(
        key: 'L1_NB_deg',
        name: 'L1 – NB',
        detail: 'Lower incisor inclination to NB',
        unit: CephUnit.deg,
        mean: 25,
        sd: 5,
        needs: const ['N', 'B', ..._l1],
        compute: (g) => CephGeometry.lean(g['N'] - g['B'], g['L1T'] - g['L1A']),
      ),
      CephMeasure(
        key: 'L1_NB_mm',
        name: 'L1 – NB',
        detail: 'Lower incisor ahead of NB',
        unit: CephUnit.mm,
        mean: 4,
        sd: 2,
        needs: const ['N', 'B', 'L1T'],
        compute: (g) => g.mm(CephGeometry.ahead(g['L1T'], g['N'], g['B'])),
      ),
      _interincisalAngle(130, 6),
    ],
  ),
  CephAnalysis(
    key: 'downs',
    name: 'Downs',
    detail: 'Skeletal pattern and teeth against Frankfort horizontal',
    measures: [
      const CephMeasure(
        key: 'FacialAngle',
        name: 'Facial angle',
        detail: 'FH to N–Pog',
        unit: CephUnit.deg,
        mean: 87.8,
        sd: 3.6,
        needs: [..._fh, 'N', 'Pog'],
        compute: _facialAngle,
      ),
      CephMeasure(
        key: 'Convexity',
        name: 'Angle of convexity',
        detail: 'N–A–Pog (+ when A is in front)',
        unit: CephUnit.deg,
        mean: 0,
        sd: 5.1,
        needs: const ['N', 'A', 'Pog'],
        compute: (g) {
          final bend = 180 - g.angleAt('N', 'A', 'Pog');
          return CephGeometry.ahead(g['A'], g['N'], g['Pog']) < 0 ? -bend : bend;
        },
      ),
      CephMeasure(
        key: 'ABPlane',
        name: 'A–B plane',
        detail: 'A–B to N–Pog',
        unit: CephUnit.deg,
        mean: -4.6,
        sd: 3.7,
        needs: const ['A', 'B', 'N', 'Pog'],
        compute: (g) => -CephGeometry.lean(g['N'] - g['Pog'], g['A'] - g['B']),
      ),
      _mandibularPlane('FMA', 21.9, 3.2),
      CephMeasure(
        key: 'YAxis',
        name: 'Y-axis',
        detail: 'FH to S–Gn',
        unit: CephUnit.deg,
        mean: 59.4,
        sd: 3.8,
        needs: const [..._fh, 'S', 'Gn'],
        compute: (g) => CephGeometry.turn(g['Or'] - g['Po'], g['Gn'] - g['S']),
      ),
      CephMeasure(
        key: 'FH_OP',
        name: 'Cant of occlusal plane',
        detail: 'FH to occlusal plane',
        unit: CephUnit.deg,
        mean: 9.3,
        sd: 3.8,
        needs: const [..._fh, 'U1T', 'L1T', 'Mo'],
        compute: (g) => CephGeometry.turn(g['Or'] - g['Po'], g.incisal - g['Mo']),
      ),
      _interincisalAngle(135.4, 5.8),
      CephMeasure(
        key: 'L1_OP',
        name: 'L1 – Occlusal plane',
        detail: 'Lower incisor from upright to the occlusal plane',
        unit: CephUnit.deg,
        mean: 14.5,
        sd: 3.5,
        needs: const [..._l1, 'U1T', 'Mo'],
        compute: (g) => CephGeometry.between(g['L1T'] - g['L1A'], g['Mo'] - g.incisal) - 90,
      ),
      const CephMeasure(
        key: 'L1_MP',
        name: 'L1 – Mandibular plane',
        detail: 'Lower incisor to Go–Me',
        unit: CephUnit.deg,
        mean: 91.4,
        sd: 3.8,
        needs: [..._l1, ..._mp],
        compute: _impa,
      ),
      CephMeasure(
        key: 'U1_APog',
        name: 'U1 – A-Pog',
        detail: 'Upper incisor ahead of A–Pog',
        unit: CephUnit.mm,
        mean: 2.7,
        sd: 1.8,
        needs: const ['U1T', 'A', 'Pog'],
        compute: (g) => g.mm(CephGeometry.ahead(g['U1T'], g['A'], g['Pog'])),
      ),
    ],
  ),
  CephAnalysis(
    key: 'tweed',
    name: 'Tweed',
    detail: 'The Tweed triangle: FH, mandibular plane, lower incisor',
    measures: [
      _mandibularPlane('FMA', 25, 3),
      const CephMeasure(
        key: 'IMPA',
        name: 'IMPA',
        detail: 'Lower incisor to mandibular plane',
        unit: CephUnit.deg,
        mean: 90,
        sd: 5,
        needs: [..._l1, ..._mp],
        compute: _impa,
      ),
      CephMeasure(
        key: 'FMIA',
        name: 'FMIA',
        detail: 'Lower incisor to FH (180 − FMA − IMPA)',
        unit: CephUnit.deg,
        mean: 65,
        sd: 5,
        needs: const [..._fh, ..._mp, ..._l1],
        compute: (g) => 180 - _fma(g) - _impa(g),
      ),
    ],
  ),
  CephAnalysis(
    key: 'mcnamara',
    name: 'McNamara',
    detail: 'Jaws against the Nasion perpendicular; lengths depend on face size',
    measures: [
      CephMeasure(
        key: 'A_Nperp',
        name: 'A – N perpendicular',
        detail: 'Maxilla ahead of N⊥',
        unit: CephUnit.mm,
        mean: 1,
        sd: 2,
        needs: const [..._fh, 'N', 'A'],
        compute: (g) => g.mm(CephGeometry.ahead(g['A'], g['N'], g['N'] + g.down)),
      ),
      CephMeasure(
        key: 'Pog_Nperp',
        name: 'Pog – N perpendicular',
        detail: 'Chin ahead of N⊥',
        unit: CephUnit.mm,
        mean: -1,
        sd: 3,
        needs: const [..._fh, 'N', 'Pog'],
        compute: (g) => g.mm(CephGeometry.ahead(g['Pog'], g['N'], g['N'] + g.down)),
      ),
      CephMeasure(
        key: 'CoA',
        name: 'Co – A',
        detail: 'Effective midfacial length',
        unit: CephUnit.mm,
        needs: const ['Co', 'A'],
        compute: (g) => g.mm((g['A'] - g['Co']).distance),
      ),
      CephMeasure(
        key: 'CoGn',
        name: 'Co – Gn',
        detail: 'Effective mandibular length',
        unit: CephUnit.mm,
        needs: const ['Co', 'Gn'],
        compute: (g) => g.mm((g['Gn'] - g['Co']).distance),
      ),
      CephMeasure(
        key: 'MxMd',
        name: 'Maxillomandibular difference',
        detail: 'Co–Gn minus Co–A; compare with the size table',
        unit: CephUnit.mm,
        needs: const ['Co', 'A', 'Gn'],
        compute: (g) => g.mm((g['Gn'] - g['Co']).distance - (g['A'] - g['Co']).distance),
      ),
      CephMeasure(
        key: 'LAFH',
        name: 'Lower face height',
        detail: 'ANS – Me',
        unit: CephUnit.mm,
        needs: const ['ANS', 'Me'],
        compute: (g) => g.mm((g['Me'] - g['ANS']).distance),
      ),
      _mandibularPlane('FMA', 22, 4),
      const CephMeasure(
        key: 'FacialAxis',
        name: 'Facial axis',
        detail: 'Ba–N to Pt–Gn',
        unit: CephUnit.deg,
        mean: 90,
        sd: 3.5,
        needs: _facialAxisNeeds,
        compute: _facialAxis,
      ),
      CephMeasure(
        key: 'U1_Avert',
        name: 'U1 – A vertical',
        detail: 'Upper incisor ahead of the vertical through A',
        unit: CephUnit.mm,
        mean: 5,
        sd: 1,
        needs: const [..._fh, 'A', 'U1T'],
        compute: (g) => g.mm(CephGeometry.ahead(g['U1T'], g['A'], g['A'] + g.down)),
      ),
      const CephMeasure(
        key: 'L1_APog',
        name: 'L1 – A-Pog',
        detail: 'Lower incisor ahead of A–Pog',
        unit: CephUnit.mm,
        mean: 2,
        sd: 1,
        needs: ['L1T', 'A', 'Pog'],
        compute: _l1APog,
      ),
      CephMeasure(
        key: 'Nasolabial',
        name: 'Nasolabial angle',
        detail: 'Cm – Sn – Ls',
        unit: CephUnit.deg,
        mean: 102,
        sd: 8,
        needs: const ['Cm', 'Sn', 'Ls'],
        compute: (g) => g.angleAt('Cm', 'Sn', 'Ls'),
      ),
    ],
  ),
  CephAnalysis(
    key: 'ricketts',
    name: 'Ricketts',
    detail: 'A subset: facial axis and depth, convexity, incisors and lips',
    measures: [
      const CephMeasure(
        key: 'FacialAxis',
        name: 'Facial axis',
        detail: 'Ba–N to Pt–Gn',
        unit: CephUnit.deg,
        mean: 90,
        sd: 3.5,
        needs: _facialAxisNeeds,
        compute: _facialAxis,
      ),
      const CephMeasure(
        key: 'FacialDepth',
        name: 'Facial depth',
        detail: 'FH to N–Pog',
        unit: CephUnit.deg,
        mean: 87,
        sd: 3,
        needs: [..._fh, 'N', 'Pog'],
        compute: _facialAngle,
      ),
      _mandibularPlane('FMA', 26, 4.5),
      CephMeasure(
        key: 'Convexity',
        name: 'Convexity',
        detail: 'Point A ahead of N–Pog',
        unit: CephUnit.mm,
        mean: 2,
        sd: 2,
        needs: const ['A', 'N', 'Pog'],
        compute: (g) => g.mm(CephGeometry.ahead(g['A'], g['N'], g['Pog'])),
      ),
      const CephMeasure(
        key: 'L1_APog',
        name: 'L1 – A-Pog',
        detail: 'Lower incisor ahead of A–Pog',
        unit: CephUnit.mm,
        mean: 1,
        sd: 2,
        needs: ['L1T', 'A', 'Pog'],
        compute: _l1APog,
      ),
      CephMeasure(
        key: 'L1_APog_deg',
        name: 'L1 inclination',
        detail: 'Lower incisor to A–Pog',
        unit: CephUnit.deg,
        mean: 22,
        sd: 4,
        needs: const [..._l1, 'A', 'Pog'],
        compute: (g) => CephGeometry.lean(g['A'] - g['Pog'], g['L1T'] - g['L1A']),
      ),
      _interincisalAngle(130, 6),
      CephMeasure(
        key: 'LL_E',
        name: 'Lower lip – E-line',
        detail: 'Lower lip ahead of Prn–Pog\'',
        unit: CephUnit.mm,
        mean: -2,
        sd: 2,
        needs: const ['Li', 'Prn', "Pog'"],
        compute: (g) => g.mm(CephGeometry.ahead(g['Li'], g['Prn'], g["Pog'"])),
      ),
      CephMeasure(
        key: 'UL_E',
        name: 'Upper lip – E-line',
        detail: 'Upper lip ahead of Prn–Pog\'',
        unit: CephUnit.mm,
        mean: -4,
        sd: 2,
        needs: const ['Ls', 'Prn', "Pog'"],
        compute: (g) => g.mm(CephGeometry.ahead(g['Ls'], g['Prn'], g["Pog'"])),
      ),
    ],
  ),
];

CephAnalysis cephAnalysis(String key) =>
    cephAnalyses.firstWhere((a) => a.key == key, orElse: () => cephAnalyses.first);

// ───────────────────────────── Tracing lines ─────────────────────────────

/// A line of the tracing in image space. [analysis] lines belong to the
/// chosen analysis (drawn dashed); the rest are the reference planes.
class CephLine {
  const CephLine(this.a, this.b, this.label, {this.analysis = false});

  final Offset a;
  final Offset b;
  final String label;
  final bool analysis;
}

/// Reference planes (SN, FH, palatal, occlusal, mandibular, incisor axes)
/// and the chosen analysis's own lines, for the landmarks placed so far.
List<CephLine> cephLines(String analysisKey, Map<String, Offset> p) {
  final out = <CephLine>[];
  void line(String a, String b, String label, {bool analysis = false}) {
    final pa = p[a], pb = p[b];
    if (pa != null && pb != null) out.add(CephLine(pa, pb, label, analysis: analysis));
  }

  line('S', 'N', 'SN');
  line('Po', 'Or', 'FH');
  line('PNS', 'ANS', 'PP');
  final u1t = p['U1T'], l1t = p['L1T'], mo = p['Mo'];
  if (u1t != null && l1t != null && mo != null) out.add(CephLine(mo, (u1t + l1t) / 2, 'OP'));
  line('Go', 'Me', 'MP');
  line('U1A', 'U1T', 'U1');
  line('L1A', 'L1T', 'L1');

  switch (analysisKey) {
    case 'steiner':
      line('N', 'A', 'NA', analysis: true);
      line('N', 'B', 'NB', analysis: true);
      line('Go', 'Gn', 'GoGn', analysis: true);
    case 'downs':
      line('N', 'Pog', 'N-Pog', analysis: true);
      line('A', 'B', 'AB', analysis: true);
      line('A', 'Pog', 'A-Pog', analysis: true);
      line('S', 'Gn', 'Y', analysis: true);
    case 'mcnamara':
      final po = p['Po'], or = p['Or'];
      if (po != null && or != null) {
        final down = _perpDown(po, or) * (or - po).distance * 1.6;
        final n = p['N'], a = p['A'];
        if (n != null) out.add(CephLine(n, n + down, 'N⊥', analysis: true));
        if (a != null) out.add(CephLine(a - down * 0.25, a + down * 0.25, 'A⊥', analysis: true));
      }
      line('Ba', 'N', 'Ba-N', analysis: true);
      line('Pt', 'Gn', 'Pt-Gn', analysis: true);
      line('A', 'Pog', 'A-Pog', analysis: true);
      line('Co', 'A', 'Co-A', analysis: true);
      line('Co', 'Gn', 'Co-Gn', analysis: true);
    case 'ricketts':
      line('Ba', 'N', 'Ba-N', analysis: true);
      line('Pt', 'Gn', 'Pt-Gn', analysis: true);
      line('N', 'Pog', 'N-Pog', analysis: true);
      line('A', 'Pog', 'A-Pog', analysis: true);
      line('Prn', "Pog'", 'E', analysis: true);
  }
  return out;
}

/// The soft-tissue profile, nose to chin, through the points placed.
List<Offset> cephProfile(Map<String, Offset> p) => [
      for (final id in const ['Prn', 'Cm', 'Sn', 'Ls', 'Li', "Pog'"])
        if (p[id] != null) p[id]!,
    ];
