import 'dart:convert';

/// SOAP section a physiotherapy field belongs to. Drives both the review
/// form's grouping and the order of the saved visit summary.
enum SoapSection {
  subjective('Subjective', 'S'),
  objective('Objective', 'O'),
  assessment('Assessment', 'A'),
  plan('Plan', 'P');

  const SoapSection(this.title, this.letter);
  final String title;
  final String letter;
}

/// A free-text physio field (e.g. mechanism of onset, palpation findings).
class PhysioTextSpec {
  const PhysioTextSpec(
    this.key,
    this.label,
    this.section, {
    required this.hint,
    required this.instruction,
    this.maxLines = 3,
    this.compact = false,
  });

  final String key;
  final String label;
  final SoapSection section;
  final String hint;

  /// Tells the model what belongs in this field (sent as schema description).
  final String instruction;
  final int maxLines;

  /// Short single-value fields (pain scores) laid out side by side.
  final bool compact;
}

/// A list-of-phrases physio field, edited as chips.
class PhysioListSpec {
  const PhysioListSpec(
    this.key,
    this.label,
    this.section, {
    required this.hint,
    required this.instruction,
  });

  final String key;
  final String label;
  final SoapSection section;
  final String hint;
  final String instruction;
}

class PhysioColumn {
  const PhysioColumn(this.key, this.label, {this.flex = 1});
  final String key;
  final String label;
  final int flex;
}

/// A repeating structured measurement (ROM, MMT, special tests, HEP...).
/// The first column is the row's identity — rows without it are dropped.
class PhysioTableSpec {
  const PhysioTableSpec(
    this.key,
    this.label,
    this.section, {
    required this.columns,
    required this.addLabel,
    required this.instruction,
  });

  final String key;
  final String label;
  final SoapSection section;
  final List<PhysioColumn> columns;
  final String addLabel;
  final String instruction;
}

/// Physiotherapy-specific findings captured by the AI Scribe, on top of the
/// general fields on [ConsultationNote].
///
/// Field definitions live in [textSpecs], [listSpecs] and [tableSpecs] — the
/// AI schema, the review form and the visit summary are all generated from
/// them, so adding a field is a one-line change here. Stored as one JSON
/// string, which keeps older notes (no physio data) readable as empty.
class PhysioFindings {
  const PhysioFindings({
    this.text = const {},
    this.lists = const {},
    this.tables = const {},
  });

  static const empty = PhysioFindings();

  final Map<String, String> text;
  final Map<String, List<String>> lists;
  final Map<String, List<Map<String, String>>> tables;

  static const textSpecs = <PhysioTextSpec>[
    // Subjective
    PhysioTextSpec(
      'painNow',
      'Pain now',
      SoapSection.subjective,
      hint: 'e.g. 6/10',
      instruction:
          'Current pain intensity on a 0-10 scale (NPRS/VAS), as "n/10". '
          'Only if a number was stated.',
      compact: true,
    ),
    PhysioTextSpec(
      'painWorst',
      'At worst',
      SoapSection.subjective,
      hint: 'e.g. 8/10',
      instruction: 'Worst pain in the last 24h/week as "n/10", if stated.',
      compact: true,
    ),
    PhysioTextSpec(
      'painBest',
      'At best',
      SoapSection.subjective,
      hint: 'e.g. 2/10',
      instruction: 'Least pain as "n/10", if stated.',
      compact: true,
    ),
    PhysioTextSpec(
      'painNature',
      'Pain behaviour',
      SoapSection.subjective,
      hint: 'e.g. Sharp, radiating to posterior thigh, intermittent',
      instruction:
          'Quality and behaviour of pain: type (sharp/dull/burning), '
          'radiation, pins and needles/numbness, constant vs intermittent.',
    ),
    PhysioTextSpec(
      'onset',
      'History of presenting complaint',
      SoapSection.subjective,
      hint: 'e.g. Lifting injury 3 weeks ago, gradually worsening',
      instruction:
          'Mechanism of injury or onset, duration, and course since '
          '(improving/worsening). Include prior treatment for this problem.',
      maxLines: 4,
    ),
    PhysioTextSpec(
      'pattern24h',
      '24-hour pattern',
      SoapSection.subjective,
      hint: 'e.g. Morning stiffness ~30 min, worse end of day',
      instruction:
          'Diurnal pattern: morning stiffness and its duration, night pain, '
          'end-of-day behaviour.',
    ),
    PhysioTextSpec(
      'history',
      'Relevant medical history',
      SoapSection.subjective,
      hint: 'e.g. Diabetic, previous ACL repair (2019), MRI shows L4-5 bulge',
      instruction:
          'Past medical/surgical history, comorbidities, imaging or '
          'investigation results, occupation and activity level mentioned.',
      maxLines: 4,
    ),
    PhysioTextSpec(
      'hepAdherence',
      'Home exercise adherence',
      SoapSection.subjective,
      hint: 'e.g. Doing exercises once daily, missed 2 days',
      instruction:
          'On follow-up visits: how the patient has been doing their home '
          'exercises and their response to the last session.',
    ),
    PhysioTextSpec(
      'patientGoals',
      "Patient's goals",
      SoapSection.subjective,
      hint: 'e.g. Return to cricket, climb stairs without pain',
      instruction: 'What the patient says they want to get back to.',
    ),
    // Objective
    PhysioTextSpec(
      'observation',
      'Observation, posture & gait',
      SoapSection.objective,
      hint: 'e.g. Antalgic gait, forward head posture, mild swelling R knee',
      instruction:
          'Observed posture, gait, swelling, deformity, muscle wasting, '
          'transfers and use of walking aids.',
    ),
    PhysioTextSpec(
      'palpation',
      'Palpation',
      SoapSection.objective,
      hint: 'e.g. Tender R L4-5 paraspinals, trigger point upper trapezius',
      instruction: 'Tenderness, spasm, trigger points, warmth on palpation.',
    ),
    PhysioTextSpec(
      'neuro',
      'Neurological screen',
      SoapSection.objective,
      hint: 'e.g. SLR R 40° +ve, L5 dermatome reduced, reflexes normal',
      instruction:
          'Dermatomes, myotomes, reflexes, neural tension tests (SLR, '
          'slump, ULTT) with results.',
    ),
    // Assessment
    PhysioTextSpec(
      'progress',
      'Progress & response to treatment',
      SoapSection.assessment,
      hint: 'e.g. Pain reduced 7→4/10, flexion improved 20° since last visit',
      instruction:
          "The clinician's statements about progress since earlier "
          'sessions, response to treatment today, and barriers to recovery.',
      maxLines: 4,
    ),
    // Plan
    PhysioTextSpec(
      'planFrequency',
      'Plan of care',
      SoapSection.plan,
      hint: 'e.g. 3 sessions/week for 4 weeks, then review',
      instruction:
          'Session frequency and duration, next-session plan, progression '
          'criteria, referrals or investigations advised.',
    ),
  ];

  static const listSpecs = <PhysioListSpec>[
    PhysioListSpec(
      'painLocation',
      'Pain location',
      SoapSection.subjective,
      hint: 'Add a location (with side)',
      instruction:
          'Body areas where symptoms are felt, with side, e.g. '
          '"Right lateral knee", "Lower back, central".',
    ),
    PhysioListSpec(
      'aggravating',
      'Aggravating factors',
      SoapSection.subjective,
      hint: 'Add an aggravating factor',
      instruction: 'Activities or positions that make it worse.',
    ),
    PhysioListSpec(
      'easing',
      'Easing factors',
      SoapSection.subjective,
      hint: 'Add an easing factor',
      instruction: 'Activities, positions or treatments that ease it.',
    ),
    PhysioListSpec(
      'functionalLimitations',
      'Functional limitations',
      SoapSection.subjective,
      hint: 'Add a limitation',
      instruction:
          'Daily activities the patient cannot do or finds difficult, e.g. '
          '"Sitting > 20 min", "Squatting to use Indian toilet".',
    ),
    PhysioListSpec(
      'redFlags',
      'Red flags present',
      SoapSection.subjective,
      hint: 'Add a red flag',
      instruction:
          'Serious-pathology warning signs reported as PRESENT: e.g. '
          'bladder/bowel change, saddle anaesthesia, unexplained weight '
          'loss, night pain unrelieved by rest, fever, progressive weakness, '
          'history of cancer, trauma with suspected fracture.',
    ),
    PhysioListSpec(
      'redFlagsCleared',
      'Red flags screened (negative)',
      SoapSection.subjective,
      hint: 'Add a screened red flag',
      instruction:
          'Red flags the clinician asked about and the patient DENIED, e.g. '
          '"No bladder/bowel change".',
    ),
    PhysioListSpec(
      'shortTermGoals',
      'Short-term goals',
      SoapSection.plan,
      hint: 'Add a short-term goal',
      instruction:
          'Measurable goals for the next ~2 weeks stated by the clinician.',
    ),
    PhysioListSpec(
      'longTermGoals',
      'Long-term goals',
      SoapSection.plan,
      hint: 'Add a long-term goal',
      instruction: 'Goals for the end of the treatment plan.',
    ),
  ];

  static const tableSpecs = <PhysioTableSpec>[
    PhysioTableSpec(
      'rom',
      'Range of motion',
      SoapSection.objective,
      addLabel: 'Add ROM',
      columns: [
        PhysioColumn('movement', 'Joint & movement', flex: 2),
        PhysioColumn('side', 'Side'),
        PhysioColumn('value', 'Range (°) / finding', flex: 2),
      ],
      instruction:
          'One row per movement measured. movement e.g. "Knee flexion"; '
          'side L/R/Bilateral; value with degrees and AROM/PROM, pain or '
          'end-feel, e.g. "AROM 95°, painful end range".',
    ),
    PhysioTableSpec(
      'strength',
      'Muscle strength (MMT)',
      SoapSection.objective,
      addLabel: 'Add muscle',
      columns: [
        PhysioColumn('muscle', 'Muscle / movement', flex: 2),
        PhysioColumn('side', 'Side'),
        PhysioColumn('grade', 'Grade (0–5)'),
      ],
      instruction:
          'Manual muscle testing. grade as "n/5" (with +/- if said), or '
          'dynamometer value with units.',
    ),
    PhysioTableSpec(
      'specialTests',
      'Special tests',
      SoapSection.objective,
      addLabel: 'Add test',
      columns: [
        PhysioColumn('test', 'Test', flex: 2),
        PhysioColumn('side', 'Side'),
        PhysioColumn('result', 'Result'),
      ],
      instruction:
          'Named orthopaedic tests (Lachman, McMurray, Neer, Hawkins-Kennedy, '
          'FABER, Spurling...). result "Positive"/"Negative" plus any detail.',
    ),
    PhysioTableSpec(
      'outcomeMeasures',
      'Outcome measures',
      SoapSection.objective,
      addLabel: 'Add measure',
      columns: [
        PhysioColumn('measure', 'Measure', flex: 2),
        PhysioColumn('score', 'Score'),
      ],
      instruction:
          'Standardised scores stated aloud: ODI, NDI, DASH/QuickDASH, LEFS, '
          'KOOS, SPADI, PSFS, Berg, TUG (seconds), 6MWT (metres).',
    ),
    PhysioTableSpec(
      'treatment',
      'Treatment given today',
      SoapSection.plan,
      addLabel: 'Add intervention',
      columns: [
        PhysioColumn('intervention', 'Intervention', flex: 2),
        PhysioColumn('details', 'Parameters / region', flex: 2),
        PhysioColumn('minutes', 'Minutes'),
      ],
      instruction:
          'Every intervention performed in this session: manual therapy '
          '(with technique and grade, e.g. "Maitland PA glides grade III"), '
          'electrotherapy (IFT, TENS, US with parameters), dry needling, '
          'taping, heat/cold, supervised exercise. minutes only if stated.',
    ),
    PhysioTableSpec(
      'homeExercises',
      'Home exercise programme',
      SoapSection.plan,
      addLabel: 'Add exercise',
      columns: [
        PhysioColumn('exercise', 'Exercise', flex: 2),
        PhysioColumn('dosage', 'Sets × reps / hold', flex: 2),
        PhysioColumn('frequency', 'Frequency'),
      ],
      instruction:
          'Exercises the patient was told to do at home. dosage e.g. '
          '"3 × 10, hold 5 s", "2 kg"; frequency e.g. "twice daily".',
    ),
  ];

  static final _textKeys = {for (final s in textSpecs) s.key};
  static final _listKeys = {for (final s in listSpecs) s.key};
  static final _tableSpecsByKey = {for (final s in tableSpecs) s.key: s};

  String textOf(String key) => text[key] ?? '';
  List<String> listOf(String key) => lists[key] ?? const [];
  List<Map<String, String>> tableOf(String key) => tables[key] ?? const [];

  bool get isEmpty =>
      text.values.every((v) => v.trim().isEmpty) &&
      lists.values.every((l) => l.isEmpty) &&
      tables.values.every((t) => t.isEmpty);

  /// Builds findings from the model's (or storage's) JSON, keeping only
  /// known keys and dropping blanks, "null" strings and rows whose identity
  /// column is empty. Never throws on malformed input.
  factory PhysioFindings.fromJson(Object? raw) {
    if (raw is! Map) return empty;

    final text = <String, String>{};
    for (final key in _textKeys) {
      final v = cleanString(raw[key]);
      if (v.isNotEmpty) text[key] = v;
    }

    final lists = <String, List<String>>{};
    for (final key in _listKeys) {
      final value = raw[key];
      if (value is! List) continue;
      final seen = <String>{};
      final items = value
          .map(cleanString)
          .where((e) => e.isNotEmpty && seen.add(e.toLowerCase()))
          .toList();
      if (items.isNotEmpty) lists[key] = items;
    }

    final tables = <String, List<Map<String, String>>>{};
    for (final spec in tableSpecs) {
      final value = raw[spec.key];
      if (value is! List) continue;
      final rows = value
          .whereType<Map>()
          .map(
            (r) => {for (final c in spec.columns) c.key: cleanString(r[c.key])},
          )
          .where((r) => r[spec.columns.first.key]!.isNotEmpty)
          .toList();
      if (rows.isNotEmpty) tables[spec.key] = rows;
    }

    return PhysioFindings(text: text, lists: lists, tables: tables);
  }

  Map<String, dynamic> toJson() => {
    for (final e in text.entries)
      if (e.value.trim().isNotEmpty) e.key: e.value,
    for (final e in lists.entries)
      if (e.value.isNotEmpty) e.key: e.value,
    for (final e in tables.entries)
      if (e.value.isNotEmpty && _tableSpecsByKey.containsKey(e.key))
        e.key: e.value,
  };

  String toStored() => jsonEncode(toJson());

  static PhysioFindings fromStored(Object? value) {
    if (value is! String || value.isEmpty) return empty;
    try {
      return PhysioFindings.fromJson(jsonDecode(value));
    } catch (_) {
      return empty;
    }
  }

  /// Formats one table row for the text summary, e.g.
  /// "Knee flexion (R): AROM 95°".
  static String formatRow(PhysioTableSpec spec, Map<String, String> row) {
    final cols = spec.columns;
    final name = row[cols.first.key]?.trim() ?? '';
    final hasSide = cols.any((c) => c.key == 'side');
    final side = hasSide ? (row['side']?.trim() ?? '') : '';
    final rest = cols
        .skip(1)
        .where((c) => c.key != 'side')
        .map((c) {
          final v = row[c.key]?.trim() ?? '';
          if (v.isEmpty) return '';
          return c.key == 'minutes' ? '$v min' : v;
        })
        .where((v) => v.isNotEmpty)
        .join(', ');
    final head = side.isEmpty ? name : '$name ($side)';
    return rest.isEmpty ? head : '$head: $rest';
  }

  static String cleanString(Object? value) {
    if (value is num) return value.toString();
    if (value is! String) return '';
    final trimmed = value.trim();
    return trimmed.toLowerCase() == 'null' ? '' : trimmed;
  }
}
