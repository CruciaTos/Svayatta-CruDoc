import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Stroke icons for the homeopathy case sheet, drawn like [CruIcons]
/// (24-unit viewBox, round caps), so the sections match the rest of the app.
abstract final class HomeopathyIcons {
  /// A. Case overview.
  static const clipboard = CruIconData(
    'M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6'
    'a2 2 0 0 1 2-2h2M9 12h6M9 16h4',
    rects: [(8, 2, 8, 4, 1)],
  );

  /// B. Chief complaint: where it hurts.
  static const target = CruIconData(
    '',
    circles: [(12, 12, 9), (12, 12, 5), (12, 12, 1)],
  );

  /// C. Modalities: what makes it better or worse.
  static const sliders = CruIconData(
    'M20 6h-7M9 6H4M20 12h-9M7 12H4M20 18h-5M11 18H4'
    'M13 4v4M7 10v4M15 16v4',
  );

  /// D. Generals and thermal state.
  static const thermometer = CruIconData(
    'M14 4v10.5a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0ZM12 18v-6',
  );

  /// E. Physical symptoms by system.
  static const pulse = CruIconData('M21 12h-4l-3 8-4-16-3 8H3');

  /// F. Female history; Female & endocrine questionnaire.
  static const female = CruIconData(
    'M12 15v6M9 18.5h6',
    circles: [(12, 9, 5.5)],
  );

  /// G. Mental & emotional state.
  static const heart = CruIconData(
    'M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2'
    '-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7Z',
  );

  /// Detailed personality (Q1–Q18).
  static const person = CruIconData(
    'M4.5 20c.7-3.6 3.8-6 7.5-6s6.8 2.4 7.5 6',
    circles: [(12, 8, 4)],
  );

  /// H. Dreams & sleep.
  static const moon = CruIconData(
    'M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5Z',
  );

  /// Childhood history; Children questionnaire.
  static const child = CruIconData(
    'M9 10h.01M15 10h.01M9.5 14.5a3.5 3.5 0 0 0 5 0',
    circles: [(12, 12, 9)],
  );

  /// I. Sexual history (locked until opened).
  static const lock = CruIconData(
    'M8 10.5V8a4 4 0 0 1 8 0v2.5',
    rects: [(5, 10.5, 14, 10, 2.5)],
  );

  /// J. Past medical & family history.
  static const history = CruIconData(
    'M3 12a9 9 0 1 0 2.6-6.4L3 8M3 3.5V8h4.5M12 7.5V12l3 2',
  );

  /// K. Physical examination.
  static const stethoscope = CruIconData(
    'M6 3H5a2 2 0 0 0-2 2v4a5 5 0 0 0 10 0V5a2 2 0 0 0-2-2h-1'
    'M8 14v1a5 5 0 0 0 10 0v-2.5',
    circles: [(18, 10.5, 2)],
  );

  /// L. Investigations & lab reports.
  static const flask = CruIconData(
    'M9.5 3v6.5L4.6 18a2 2 0 0 0 1.7 3h11.4a2 2 0 0 0 1.7-3l-4.9-8.5V3'
    'M8.5 3h7M7 15h10',
  );

  /// M. Strange, rare & peculiar symptoms.
  static const star = CruIconData(
    'm12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3l-5.6 2.9 1.1-6.2'
    'L3 9.6l6.2-.9Z',
  );

  /// N. Repertorization & remedy.
  static const pill = CruIconData(
    'm10.5 20.5 10-10a5 5 0 0 0-7-7l-10 10a5 5 0 0 0 7 7ZM8.5 8.5l7 7',
  );

  /// O. Follow-up.
  static const refresh = CruIconData(
    'M3 12a9 9 0 0 1 15.4-6.4L21 8M21 3.5V8h-4.5'
    'M21 12a9 9 0 0 1-15.4 6.4L3 16M3 20.5V16h4.5',
  );

  /// Acute questionnaire.
  static const bolt = CruIconData('M13 2.5 4 14h7.5l-1 7.5L20 10h-7.5Z');

  /// Unlock a protected section.
  static const eye = CruIconData(
    'M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z',
    circles: [(12, 12, 3)],
  );

  /// Email on the contact card.
  static const mail = CruIconData(
    'm3.5 7.5 8.5 6 8.5-6',
    rects: [(3, 5, 18, 14, 2.5)],
  );
}
