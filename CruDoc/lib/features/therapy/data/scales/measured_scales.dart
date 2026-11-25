import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';

// Outcome measures that are a single figure the physio measures, rather than
// a questionnaire the patient fills in.
//
// These are defined in code rather than loaded from an asset, because there
// is no instrument text to license, translate or keep in step with a
// publisher: a stopwatch reading and a distance walked are just numbers. The
// questionnaires live in `assets/outcome_scales/` for exactly the opposite
// reason.
//
// Neither carries bands. Published cut-offs for both depend on the
// population — age, diagnosis, whether the patient uses an aid — and a band
// applied automatically would label a fit forty-year-old against thresholds
// drawn from frail elderly cohorts. The figure is reported, and the physio
// reads it against the right reference.

/// Timed Up and Go: time to rise from a chair, walk 3 m, turn, return and
/// sit.
const ScaleDef kTugScale = ScaleDef(
  id: 'tug',
  name: 'Timed Up and Go',
  short: 'TUG',
  region: 'Mobility and balance',
  kind: ScaleKind.measured,
  unit: 's',
  // A slower time is a worse result.
  higherIsBetter: false,
  source: 'Podsiadlo & Richardson',
  instruction:
      'Standard chair with arms, 3 m marked out. The patient wears their '
      'usual footwear and uses their usual walking aid. One practice run, '
      'then time one trial on the word go until they are seated again.',
  usageNote:
      'Cut-offs for falls risk differ by population, so no interpretation '
      'band is applied. Record the aid used in the note — the same patient '
      'with and without a stick is not the same measurement.',
  // Deliberately absent: reported MDC ranges widely between populations,
  // and a single figure here would turn noise into progress.
  mdc: null,
);

/// Six Minute Walk Test: distance covered walking for six minutes.
const ScaleDef kSixMinuteWalkScale = ScaleDef(
  id: 'sixmwt',
  name: 'Six Minute Walk Test',
  short: '6MWT',
  region: 'Cardiopulmonary endurance',
  kind: ScaleKind.measured,
  unit: 'm',
  // Further is better.
  higherIsBetter: true,
  source: 'American Thoracic Society guideline',
  instruction:
      'A flat 30 m course, marked at both ends. The patient walks as far as '
      'they can in six minutes, resting if they need to without stopping '
      'the clock. Standard encouragement only, at each minute.',
  usageNote:
      'Record rests, oxygen, and why the test stopped early if it did. '
      'Predicted normals depend on age, sex and height, so no band is '
      'applied here.',
  mdc: null,
);

/// The measures that need no asset file.
const List<ScaleDef> kBuiltInScales = [kTugScale, kSixMinuteWalkScale];
