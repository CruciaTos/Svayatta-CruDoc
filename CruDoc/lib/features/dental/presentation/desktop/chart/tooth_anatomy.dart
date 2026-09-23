import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';

/// The shape family a tooth is drawn from.
enum ToothKind { centralIncisor, lateralIncisor, canine, premolar, molar }

/// Average tooth sizes in millimetres, so the 2D row and the 3D jaws are
/// in proportion: crown width (mesiodistal), crown depth (buccolingual),
/// crown height, root length and how many roots.
class ToothSpec {
  const ToothSpec({
    required this.number,
    required this.kind,
    required this.upper,
    required this.primary,
    required this.md,
    required this.bl,
    required this.crown,
    required this.root,
    required this.roots,
  });

  final String number;
  final ToothKind kind;
  final bool upper;
  final bool primary;
  final double md;
  final double bl;
  final double crown;
  final double root;
  final int roots;

  /// Patient's right side (quadrants 1, 4, 5, 8): drawn on the left.
  bool get patientRight {
    final q = int.parse(number[0]);
    return q == 1 || q == 4 || q == 5 || q == 8;
  }

  /// 1 (central incisor) to 8 (wisdom tooth).
  int get position => int.parse(number[1]);

  static final Map<String, ToothSpec> _cache = {};

  static ToothSpec of(String number) =>
      _cache.putIfAbsent(number, () => _build(number));

  static ToothSpec _build(String n) {
    final q = int.parse(n[0]);
    final p = int.parse(n[1]);
    final primary = q >= 5;
    final upper = q == 1 || q == 2 || q == 5 || q == 6;
    // (md, bl, crown, root, roots)
    final (double, double, double, double, int) d;
    final ToothKind kind;
    if (!primary) {
      kind = switch (p) {
        1 => ToothKind.centralIncisor,
        2 => ToothKind.lateralIncisor,
        3 => ToothKind.canine,
        4 || 5 => ToothKind.premolar,
        _ => ToothKind.molar,
      };
      d = upper
          ? switch (p) {
              1 => (8.5, 7.0, 10.5, 13.0, 1),
              2 => (6.5, 6.0, 9.0, 13.0, 1),
              3 => (7.5, 8.0, 10.0, 17.0, 1),
              4 => (7.0, 9.0, 8.5, 14.0, 2),
              5 => (6.5, 9.0, 8.5, 14.0, 1),
              6 => (10.0, 11.0, 7.5, 13.0, 3),
              7 => (9.0, 11.0, 7.0, 12.0, 3),
              _ => (8.5, 10.0, 6.5, 11.0, 3),
            }
          : switch (p) {
              1 => (5.0, 6.0, 9.0, 12.5, 1),
              2 => (5.5, 6.5, 9.5, 14.0, 1),
              3 => (7.0, 7.5, 11.0, 16.0, 1),
              4 => (7.0, 7.5, 8.5, 14.0, 1),
              5 => (7.0, 8.0, 8.0, 14.5, 1),
              6 => (11.0, 10.5, 7.5, 14.0, 2),
              7 => (10.5, 10.0, 7.0, 13.0, 2),
              _ => (10.0, 9.5, 7.0, 11.0, 2),
            };
    } else {
      kind = switch (p) {
        1 => ToothKind.centralIncisor,
        2 => ToothKind.lateralIncisor,
        3 => ToothKind.canine,
        _ => ToothKind.molar,
      };
      d = upper
          ? switch (p) {
              1 => (6.5, 5.0, 6.0, 10.0, 1),
              2 => (5.1, 4.0, 5.6, 10.0, 1),
              3 => (7.0, 7.0, 6.5, 13.0, 1),
              4 => (7.3, 8.5, 5.0, 10.0, 3),
              _ => (8.2, 10.0, 5.7, 11.0, 3),
            }
          : switch (p) {
              1 => (4.2, 4.0, 5.0, 9.0, 1),
              2 => (4.1, 4.5, 5.2, 10.0, 1),
              3 => (5.0, 5.5, 6.0, 11.5, 1),
              4 => (7.7, 7.0, 6.0, 10.0, 2),
              _ => (9.9, 8.7, 5.5, 11.0, 2),
            };
    }
    return ToothSpec(
      number: n,
      kind: kind,
      upper: upper,
      primary: primary,
      md: d.$1,
      bl: d.$2,
      crown: d.$3,
      root: d.$4,
      roots: d.$5,
    );
  }

  /// Upper and lower rows for the adult or the milk-teeth chart, drawn
  /// as the dentist faces the patient.
  static (List<String>, List<String>) arches({required bool child}) => child
      ? (DentalChart.childUpper, DentalChart.childLower)
      : (DentalChart.adultUpper, DentalChart.adultLower);
}
