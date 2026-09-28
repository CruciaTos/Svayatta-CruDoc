import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/voice/domain/medical_conditions.dart';

/// Clinical entities extracted from an ongoing consultation transcript.
class ScribeLiveExtraction {
  const ScribeLiveExtraction({
    this.chiefComplaint,
    this.symptoms = const [],
    this.diagnoses = const [],
    this.medicines = const [],
    this.advice,
    this.bp,
    this.temp,
    this.pulse,
    this.painNow,
    this.painWorst,
    this.painLocation,
    this.painNature,
    this.aggravating = const [],
    this.easing = const [],
    this.functionalLimits = const [],
    this.onset,
    this.history,
    this.patientGoals,
    this.followUpDate,
    this.cuedFields = const {},
  });

  final String? chiefComplaint;
  final List<String> symptoms;
  final List<String> diagnoses;
  final List<NotedMedicine> medicines;
  final String? advice;
  final String? bp;
  final String? temp;
  final String? pulse;
  final String? painNow;
  final String? painWorst;
  final String? painLocation;
  final String? painNature;
  final List<String> aggravating;
  final List<String> easing;
  final List<String> functionalLimits;
  final String? onset;
  final String? history;
  final String? patientGoals;
  final DateTime? followUpDate;

  /// Fields for which user speech cues were detected (for immediate pending dissolve).
  final Set<String> cuedFields;

  bool get isEmpty =>
      (chiefComplaint == null || chiefComplaint!.isEmpty) &&
      symptoms.isEmpty &&
      diagnoses.isEmpty &&
      medicines.isEmpty &&
      (advice == null || advice!.isEmpty) &&
      bp == null &&
      temp == null &&
      pulse == null &&
      painNow == null &&
      painWorst == null &&
      painLocation == null &&
      painNature == null &&
      aggravating.isEmpty &&
      easing.isEmpty &&
      functionalLimits.isEmpty &&
      onset == null &&
      history == null &&
      patientGoals == null &&
      followUpDate == null;
}

class _DialogueContext {
  const _DialogueContext({
    this.painScore,
    this.duration,
    this.location,
    this.problem,
    this.functionalLimits = const [],
    this.aggravating = const [],
    this.easing = const [],
    this.onset,
    this.history,
    this.patientGoals,
  });

  final String? painScore;
  final String? duration;
  final String? location;
  final String? problem;
  final List<String> functionalLimits;
  final List<String> aggravating;
  final List<String> easing;
  final String? onset;
  final String? history;
  final String? patientGoals;
}

/// Real-time clinical entity extractor for AI Scribe consultations.
/// Processes speech transcripts on the fly and populates structured consultation fields.
class ScribeLiveExtractor {
  const ScribeLiveExtractor();

  static final _symptomDictionary = <String>{
    'pain',
    'severe pain',
    'swelling',
    'stiffness',
    'morning stiffness',
    'burning sensation',
    'numbness',
    'tingling',
    'pins and needles',
    'weakness',
    'muscle weakness',
    'instability',
    'giving way',
    'clicking',
    'crepitus',
    'locking',
    'restricted movement',
    'limited mobility',
    'spasm',
    'muscle spasm',
    'cramps',
    'tenderness',
    'fatigue',
    'fever',
    'high fever',
    'chills',
    'cough',
    'dry cough',
    'sore throat',
    'breathlessness',
    'shortness of breath',
    'headache',
    'dizziness',
    'vertigo',
    'nausea',
    'vomiting',
    'loss of appetite',
    'joint stiffness',
    'joint pain',
    'radiating pain',
    'aching',
    'difficulty walking',
    'unable to walk',
    'unable to walk properly',
  };

  static final _commonMedications = <String, ({String defaultDose, String defaultFreq})>{
    'paracetamol': (defaultDose: '650 mg', defaultFreq: '1 tab TDS'),
    'dolo': (defaultDose: '650 mg', defaultFreq: '1 tab TDS'),
    'crocin': (defaultDose: '650 mg', defaultFreq: '1 tab SOS'),
    'calpol': (defaultDose: '500 mg', defaultFreq: '1 tab TDS'),
    'combiflam': (defaultDose: '1 tab', defaultFreq: 'BD after food'),
    'ibuprofen': (defaultDose: '400 mg', defaultFreq: '1 tab BD after food'),
    'diclofenac': (defaultDose: '50 mg', defaultFreq: '1 tab BD after food'),
    'aceclofenac': (defaultDose: '100 mg', defaultFreq: '1 tab BD after food'),
    'zerodol': (defaultDose: '100 mg', defaultFreq: '1 tab BD'),
    'voveran': (defaultDose: '50 mg', defaultFreq: '1 tab BD'),
    'tramadol': (defaultDose: '50 mg', defaultFreq: '1 tab SOS'),
    'ultracet': (defaultDose: '1 tab', defaultFreq: 'BD SOS'),
    'pantoprazole': (defaultDose: '40 mg', defaultFreq: '1 tab OD before breakfast'),
    'pan': (defaultDose: '40 mg', defaultFreq: '1 tab OD before food'),
    'pan d': (defaultDose: '1 cap', defaultFreq: 'OD before breakfast'),
    'omeprazole': (defaultDose: '20 mg', defaultFreq: '1 cap OD'),
    'omez': (defaultDose: '20 mg', defaultFreq: '1 cap OD before breakfast'),
    'rabeprazole': (defaultDose: '20 mg', defaultFreq: '1 tab OD'),
    'cetirizine': (defaultDose: '10 mg', defaultFreq: '1 tab at bedtime'),
    'levocetirizine': (defaultDose: '5 mg', defaultFreq: '1 tab HS'),
    'montelukast': (defaultDose: '10 mg', defaultFreq: '1 tab at night'),
    'allegra': (defaultDose: '120 mg', defaultFreq: '1 tab OD'),
    'amoxicillin': (defaultDose: '500 mg', defaultFreq: '1 cap TDS for 5 days'),
    'augmentin': (defaultDose: '625 mg', defaultFreq: '1 tab BD for 5 days'),
    'azithromycin': (defaultDose: '500 mg', defaultFreq: '1 tab OD for 3 days'),
    'cefixime': (defaultDose: '200 mg', defaultFreq: '1 tab BD for 5 days'),
    'ciprofloxacin': (defaultDose: '500 mg', defaultFreq: '1 tab BD for 5 days'),
    'metformin': (defaultDose: '500 mg', defaultFreq: '1 tab BD with meals'),
    'glycomet': (defaultDose: '500 mg', defaultFreq: '1 tab BD'),
    'glimepiride': (defaultDose: '1 mg', defaultFreq: '1 tab OD before breakfast'),
    'teneligliptin': (defaultDose: '20 mg', defaultFreq: '1 tab OD'),
    'telmisartan': (defaultDose: '40 mg', defaultFreq: '1 tab OD morning'),
    'amlodipine': (defaultDose: '5 mg', defaultFreq: '1 tab OD'),
    'atorvastatin': (defaultDose: '10 mg', defaultFreq: '1 tab at bedtime'),
    'calcium': (defaultDose: '500 mg', defaultFreq: '1 tab OD after lunch'),
    'shelcal': (defaultDose: '500 mg', defaultFreq: '1 tab OD after food'),
    'vitamin d3': (defaultDose: '60,000 IU', defaultFreq: 'Once weekly for 8 weeks'),
    'calcirol': (defaultDose: '60,000 IU', defaultFreq: 'Once weekly'),
    'neurobion': (defaultDose: '1 tab', defaultFreq: 'OD for 30 days'),
    'methylcobalamin': (defaultDose: '1500 mcg', defaultFreq: '1 tab OD'),
    'pregabalin': (defaultDose: '75 mg', defaultFreq: '1 cap HS'),
    'gabapentin': (defaultDose: '100 mg', defaultFreq: '1 tab at bedtime'),
    'thiocolchicoside': (defaultDose: '4 mg', defaultFreq: '1 tab BD'),
    'baclofen': (defaultDose: '10 mg', defaultFreq: '1 tab BD'),
    'volini': (defaultDose: 'Gel', defaultFreq: 'Apply locally 2-3 times daily'),
    'omnigel': (defaultDose: 'Gel', defaultFreq: 'Apply locally twice daily'),
    'moov': (defaultDose: 'Spray', defaultFreq: 'Apply locally SOS'),
  };

  /// Detects which fields are being cued or spoken in quick/fast transcript,
  /// so that `AiBlurReveal` can immediately dissolve the outgoing content into smoke.
  Set<String> detectFieldCues(String rawText) {
    final text = rawText.toLowerCase();
    final cued = <String>{};

    if (RegExp(r'\b(complaint|problem|c/o|complaining|came with|suffering from|pain|ache|fever)\b').hasMatch(text)) {
      cued.add('chiefComplaint');
    }
    if (RegExp(r'\b(symptom|swelling|stiffness|tingling|numbness|clicking|weakness|fever|cough|headache)\b').hasMatch(text)) {
      cued.add('symptoms');
    }
    if (RegExp(r'\b(diagnos|impression|condition|spondylosis|arthritis|tear|syndrome|radiculopathy)\b').hasMatch(text)) {
      cued.add('diagnoses');
    }
    if (RegExp(r'\b(medicine|tablet|capsule|mg|dose|syrup|gel|spray|paracetamol|painkiller|prescrib|take this)\b').hasMatch(text)) {
      cued.add('medicines');
    }
    if (RegExp(r'\b(bp|blood pressure)\b').hasMatch(text)) {
      cued.add('bp');
    }
    if (RegExp(r'\b(temp|temperature|fever)\b').hasMatch(text)) {
      cued.add('temp');
    }
    if (RegExp(r'\b(pulse|heart rate|bpm)\b').hasMatch(text)) {
      cued.add('pulse');
    }
    if (RegExp(r'\b(pain|nprs|vas|scale of 10|out of 10)\b').hasMatch(text)) {
      cued.addAll(['painNow', 'painWorst', 'painNature', 'painLocation']);
    }
    if (RegExp(r'\b(advise|advice|avoid|precaution|hot pack|ice pack|exercise|rest|water)\b').hasMatch(text)) {
      cued.add('advice');
    }
    if (RegExp(r'\b(aggravat|wors|increas|trigger|bend|walk|stair|sit)\b').hasMatch(text)) {
      cued.add('aggravating');
    }
    if (RegExp(r'\b(relie|eas|better\s+with|calm|rest|pack|ice|heat)\b').hasMatch(text)) {
      cued.add('easing');
    }
    if (RegExp(r'\b(limit|cannot|can\x27t|unable|trouble|difficult)\b').hasMatch(text)) {
      cued.add('functionalLimits');
    }
    if (RegExp(r'\b(onset|start|began|mechanis|lift|fall|twist)\b').hasMatch(text)) {
      cued.add('onset');
    }
    if (RegExp(r'\b(past\s+history|medical\s+history|diabet|hypertens|bp|asthma|surger)\b').hasMatch(text)) {
      cued.add('history');
    }
    if (RegExp(r'\b(goal|aim|want\s+to|return\s+to|get\s+back)\b').hasMatch(text)) {
      cued.add('patientGoals');
    }

    return cued;
  }

  /// Extracts structured consultation entities from speech transcript with
  /// multi-turn conversational context understanding and negation detection.
  ScribeLiveExtraction extract(String rawText) {
    if (rawText.trim().isEmpty) return const ScribeLiveExtraction();
    final text = rawText.trim();
    final lower = text.toLowerCase();

    final cued = detectFieldCues(text);
    final context = _analyzeDialogueContext(text);

    var chiefComplaint = _extractChiefComplaint(text, lower);
    if (chiefComplaint == null && context.location != null) {
      final loc = context.location!;
      final dur = context.duration;
      final problem = context.problem ?? 'Severe pain';
      chiefComplaint = _formatSentence(dur != null ? '$problem on $loc for $dur' : '$problem on $loc');
    }

    final symptoms = _extractSymptoms(lower, context);
    final diagnoses = _extractDiagnoses(text, lower);
    final medicines = _extractMedicines(lower);
    final advice = _extractAdvice(text, lower);
    final vitals = _extractVitals(lower);
    final pain = _extractPain(lower, context);
    final followUp = _extractFollowUp(lower);

    return ScribeLiveExtraction(
      chiefComplaint: chiefComplaint,
      symptoms: symptoms,
      diagnoses: diagnoses,
      medicines: medicines,
      advice: advice,
      bp: vitals['bp'],
      temp: vitals['temp'],
      pulse: vitals['pulse'],
      painNow: pain['painNow'],
      painWorst: pain['painWorst'],
      painLocation: pain['painLocation'],
      painNature: pain['painNature'],
      aggravating: context.aggravating,
      easing: context.easing,
      functionalLimits: context.functionalLimits,
      onset: context.onset,
      history: context.history,
      patientGoals: context.patientGoals,
      followUpDate: followUp,
      cuedFields: cued,
    );
  }

  /// Analyzes question-answer pairs and conversational context across turns.
  _DialogueContext _analyzeDialogueContext(String text) {
    String? painScore;
    String? location;
    String? duration;
    String? problem;
    String? onset;
    String? history;
    String? patientGoals;
    final functionalLimits = <String>{};
    final aggravating = <String>{};
    final easing = <String>{};

    final turns = text.split(RegExp(r'\n+|\s+(?=(?:Doctor|Patient):)'));

    for (var i = 0; i < turns.length; i++) {
      final turn = turns[i].trim();
      final lower = turn.toLowerCase();
      final nextLower = (i + 1 < turns.length) ? turns[i + 1].trim().toLowerCase() : '';
      final window = nextLower.isNotEmpty ? '$lower $nextLower' : lower;

      // 1. Pain score inquiry (Doctor question -> Patient answer)
      if (lower.contains('intensity') ||
          lower.contains('rate') ||
          lower.contains('out of 10') ||
          lower.contains('scale of 10') ||
          lower.contains('5 or 10') ||
          lower.contains('how bad is the pain')) {
        final scoreRegex = RegExp(
          r'\b(?:say|at|around|is|it\x27s)?\s*(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)\s*(?:out of 10|\/10|on 10|out of rick ten)?\b',
        );
        final sm = scoreRegex.firstMatch(window);
        if (sm != null) {
          final s = _wordToDigit(sm.group(1) ?? '');
          if (s != null && s <= 10) {
            painScore = '$s/10';
          }
        }
      }

      // 2. Duration / onset
      final durRegex = RegExp(r'\b(?:for|since|it\x27s been|it has been|past)?\s*(\d+\s*(?:days?|weeks?|months?|years?))\b');
      final dm = durRegex.firstMatch(lower);
      if (dm != null) {
        duration ??= dm.group(1);
      }

      // 3. Location inquiry or complaint
      for (final loc in [
        'right side', 'left side', 'lower back', 'right knee', 'left knee',
        'right shoulder', 'left shoulder', 'neck', 'cervical', 'lumbar',
        'right ankle', 'left ankle', 'right wrist', 'left wrist', 'hip',
      ]) {
        if (lower.contains(loc) || nextLower.contains(loc)) {
          location = _formatTitle(loc);
          break;
        }
      }

      // 4. Complaint problem type
      if (lower.contains('severe pain') || lower.contains('very severe') || nextLower.contains('severe pain')) {
        problem = 'Severe pain';
      }

      // 5. Functional limitations
      for (final item in [
        ('unable to walk properly', 'Unable To Walk Properly'),
        ('difficulty walking', 'Difficulty Walking'),
        ('cannot walk', 'Unable To Walk Properly'),
        ("haven't been able to walk", 'Unable To Walk Properly'),
        ('cannot bend forward', 'Cannot Bend Forward'),
        ('difficulty bending', 'Difficulty Bending'),
        ('unable to bend', 'Difficulty Bending'),
        ('difficulty climbing stairs', 'Difficulty Climbing Stairs'),
        ('cannot climb stairs', 'Difficulty Climbing Stairs'),
        ('unable to climb stairs', 'Difficulty Climbing Stairs'),
        ('unable to lift arm', 'Unable To Lift Arm Overhead'),
        ('cannot raise arm', 'Unable To Lift Arm Overhead'),
        ('difficulty lifting arm', 'Unable To Lift Arm Overhead'),
        ('difficulty sleeping', 'Difficulty Sleeping Due To Pain'),
        ('trouble sleeping', 'Difficulty Sleeping Due To Pain'),
        ('difficulty sitting', 'Difficulty With Prolonged Sitting'),
        ('cannot sit for long', 'Difficulty With Prolonged Sitting'),
      ]) {
        final trigger = item.$1;
        final display = item.$2;
        if ((lower.contains(trigger) || nextLower.contains(trigger)) &&
            !_isNegated(trigger, window)) {
          functionalLimits.add(display);
        }
      }

      // 6. Aggravating factors
      if (window.contains('worse') ||
          window.contains('aggravat') ||
          window.contains('increas') ||
          window.contains('trigger') ||
          window.contains('provoke') ||
          window.contains('flares up') ||
          window.contains('hurts more')) {
        for (final item in [
          ('forward bending', 'Forward Bending'),
          ('bending forward', 'Forward Bending'),
          ('bending', 'Forward Bending'),
          ('walking long distances', 'Walking Long Distances'),
          ('walking', 'Walking'),
          ('climbing stairs', 'Climbing Stairs'),
          ('stairs', 'Climbing Stairs'),
          ('prolonged sitting', 'Prolonged Sitting'),
          ('sitting for long', 'Prolonged Sitting'),
          ('prolonged standing', 'Prolonged Standing'),
          ('standing for long', 'Prolonged Standing'),
          ('lifting weights', 'Lifting Weights'),
          ('lifting heavy', 'Lifting Weights'),
          ('lifting', 'Lifting Weights'),
          ('coughing', 'Coughing / Sneezing'),
          ('sneezing', 'Coughing / Sneezing'),
          ('twisting', 'Trunk Twisting'),
          ('running', 'Running'),
          ('overhead', 'Overhead Movements'),
        ]) {
          final phrase = item.$1;
          final display = item.$2;
          if (window.contains(phrase) && !_isNegated(phrase, window)) {
            aggravating.add(display);
          }
        }
      }

      // 7. Easing / Relieving factors
      if (window.contains('relie') ||
          window.contains('eas') ||
          window.contains('better with') ||
          window.contains('gives relief') ||
          window.contains('helps') ||
          window.contains('soothe') ||
          window.contains('calm')) {
        for (final item in [
          ('rest', 'Rest'),
          ('lying down', 'Lying Down Flat'),
          ('lying flat', 'Lying Down Flat'),
          ('hot water bag', 'Hot Water Fermentation'),
          ('hot water fermentation', 'Hot Water Fermentation'),
          ('hot fermentation', 'Hot Water Fermentation'),
          ('hot pack', 'Hot Pack'),
          ('ice pack', 'Ice Pack'),
          ('cold pack', 'Cold Pack'),
          ('gentle walking', 'Gentle Walking'),
          ('stretching', 'Gentle Stretching'),
          ('painkillers', 'Painkillers'),
          ('sitting down', 'Sitting Down'),
        ]) {
          final phrase = item.$1;
          final display = item.$2;
          if (window.contains(phrase) && !_isNegated(phrase, window)) {
            easing.add(display);
          }
        }
      }
    }

    // 8. Global Onset & Mechanism check
    final onsetRegex = RegExp(
      r'(?:onset\s+was|started|began|developed|mechanism\s+was)\s+([a-zA-Z0-9\s,]{4,60})',
      caseSensitive: false,
    );
    final om = onsetRegex.firstMatch(text);
    if (om != null) {
      final rawMatch = om.group(1)?.split(RegExp(r'[.!?;]|\band\s+also\b')).first.trim();
      if (rawMatch != null && rawMatch.length >= 4) {
        onset = _formatSentence('Started $rawMatch');
      }
    }

    // 9. Past Medical History (with negation guard)
    final historyMatches = <String>[];
    for (final item in [
      ('diabetes', 'Type 2 Diabetes Mellitus'),
      ('diabetic', 'Type 2 Diabetes Mellitus'),
      ('hypertension', 'Hypertension'),
      ('high blood pressure', 'Hypertension'),
      ('high bp', 'Hypertension'),
      ('asthma', 'Bronchial Asthma'),
      ('hypothyroid', 'Hypothyroidism'),
      ('rheumatoid', 'Rheumatoid Arthritis'),
      ('previous surgery', 'Previous Surgery'),
      ('past surgery', 'Previous Surgery'),
    ]) {
      final keyword = item.$1;
      final label = item.$2;
      if (text.toLowerCase().contains(keyword) && !_isNegated(keyword, text)) {
        if (text.toLowerCase().contains('history') ||
            text.toLowerCase().contains('past') ||
            text.toLowerCase().contains('known case') ||
            text.toLowerCase().contains('since') ||
            text.toLowerCase().contains('for 5 years') ||
            text.toLowerCase().contains('for 3 years') ||
            text.toLowerCase().contains('for 10 years')) {
          if (!historyMatches.contains(label)) {
            historyMatches.add(label);
          }
        }
      }
    }
    if (historyMatches.isNotEmpty) {
      history = historyMatches.join(', ');
    }

    // 10. Patient Goals
    final goalRegex = RegExp(
      r'(?:wants?\s+to|aims?\s+to|goal\s+is\s+to|get\s+back\s+to|return\s+to)\s+([a-zA-Z\s]{4,50})',
      caseSensitive: false,
    );
    final gm = goalRegex.firstMatch(text);
    if (gm != null) {
      final gVal = gm.group(1)?.split(RegExp(r'[.!?,;]')).first.trim();
      if (gVal != null && gVal.length >= 4) {
        patientGoals = _formatSentence(gVal);
      }
    }

    return _DialogueContext(
      painScore: painScore,
      duration: duration,
      location: location,
      problem: problem,
      functionalLimits: functionalLimits.toList(),
      aggravating: aggravating.toList(),
      easing: easing.toList(),
      onset: onset,
      history: history,
      patientGoals: patientGoals,
    );
  }

  static bool _isNegated(String term, String text) {
    final lower = text.toLowerCase();
    final termLower = term.toLowerCase();
    final termRegex = RegExp.escape(termLower);

    // Clause-level negation check: split text into clauses by [.!?;\n]
    final clauses = lower.split(RegExp(r'[.!?;]|\band\s+also\b'));
    for (final clause in clauses) {
      if (clause.contains(termLower)) {
        final negPrefix = RegExp(
          r'\b(?:no|not|denies|denied|denying|without|negative\s+for|rules?\s+out|ruled\s+out|free\s+of|absence\s+of|never\s+had)\b',
        );
        final match = negPrefix.firstMatch(clause);
        if (match != null) {
          final termIndex = clause.indexOf(termLower);
          if (match.start < termIndex) {
            return true;
          }
        }
        // Post-concept negation: e.g. "fever is absent", "swelling none"
        if (RegExp(r'\b' + termRegex + r'\s+(?:is\s+absent|is\s+ruled\s+out|none|absent|negative)\b').hasMatch(clause)) {
          return true;
        }
      }
    }
    return false;
  }

  static int? _wordToDigit(String w) {
    const map = {
      'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
      'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    };
    return int.tryParse(w) ?? map[w.toLowerCase()];
  }

  String? _extractChiefComplaint(String text, String lower) {
    // 1. Explicit intro cues
    final introRegex = RegExp(
      r'(?:chief complaint(?:\s+is)?|complaining of|c/o|complains of|presented with|came in with|came with|problem is)\s+([^.,;\n]+)',
      caseSensitive: false,
    );
    final m = introRegex.firstMatch(text);
    if (m != null) {
      final val = m.group(1)?.trim();
      if (val != null && val.length >= 4) {
        return _formatSentence(val);
      }
    }

    // 2. Anatomical + Symptom + Duration combo: e.g. "Right shoulder pain for 3 weeks"
    final durationRegex = RegExp(
      r'((?:(?:right|left|bilateral|lower|upper|cervical|lumbar)\s+)?[a-z\s]+(?:pain|ache|stiffness|swelling|fever|cough|weakness))\s+(?:for|since|past)\s+(\d+\s*(?:days?|weeks?|months?|years?))',
      caseSensitive: false,
    );
    final dm = durationRegex.firstMatch(text);
    if (dm != null) {
      final problem = dm.group(1)?.trim();
      final dur = dm.group(2)?.trim();
      if (problem != null && dur != null) {
        return _formatSentence('$problem for $dur');
      }
    }

    // 3. Conversational complaint: "feeling pain very severely on my right side ... it's been 10 days"
    final feelingPainRegex = RegExp(
      r'(?:feeling|experiencing|having|suffering\s+from)\s+([a-z\s]*(?:pain|ache|stiffness|swelling)[a-z\s]*(?:right|left|back|shoulder|knee|neck|side)[a-z\s]*?)(?:[.,;]|\s+for|\s+since|\s+it\x27s\s+been|\s+past)\s*(\d+\s*(?:days?|weeks?|months?|years?))?',
      caseSensitive: false,
    );
    final fm = feelingPainRegex.firstMatch(lower);
    if (fm != null) {
      var prob = fm.group(1)?.trim();
      final dur = fm.group(2)?.trim();
      if (prob != null && prob.isNotEmpty) {
        prob = prob
            .replaceAll(RegExp(r'\b(?:very severely|severely)\b'), 'severe')
            .replaceAll(RegExp(r'\bmy\s+'), '');
        return _formatSentence(dur != null && dur.isNotEmpty ? '$prob for $dur' : prob);
      }
    }

    return null;
  }

  List<String> _extractSymptoms(String lower, [_DialogueContext? context]) {
    final hits = <String>{};

    for (final sym in _symptomDictionary) {
      if (lower.contains(sym)) {
        // Context check: Negation! Skip if patient denies or has no symptom
        if (_isNegated(sym, lower)) continue;

        // Look for anatomical qualifier before symptom (e.g. "knee pain", "ankle swelling")
        final pattern = RegExp(
          r'\b(right|left|bilateral|knee|shoulder|neck|back|ankle|wrist|elbow|hip|chest|lumbar)?\s*' +
              RegExp.escape(sym) +
              r'\b',
        );
        final m = pattern.firstMatch(lower);
        final full = m?.group(0)?.trim() ?? sym;
        if (!_isNegated(full, lower)) {
          hits.add(_formatTitle(full));
        }
      }
    }

    // Add contextually extracted functional limitations (e.g. unable to walk properly)
    if (context != null) {
      for (final func in context.functionalLimits) {
        hits.add(_formatTitle(func));
      }
    }

    return hits.toList();
  }

  List<String> _extractDiagnoses(String text, String lower) {
    final hits = <String>{};

    // 1. Leverage medical_conditions.dart extractor
    final tokens = lower
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final fromConditions = extractMedicalConditions(tokens);
    for (final cond in fromConditions) {
      if (!_isNegated(cond, lower)) {
        hits.add(_formatTitle(cond));
      }
    }

    // 2. Explicit diagnosis patterns
    final diagRegex = RegExp(
      r'(?:diagnosis(?:\s+is)?|impression(?:\s+is)?|diagnosed with|suffering from|known case of|looks like|features of)\s+([a-zA-Z\s]{4,40})',
      caseSensitive: false,
    );
    for (final m in diagRegex.allMatches(text)) {
      final match = m.group(1)?.trim();
      if (match != null && match.isNotEmpty) {
        final clean = match.split(RegExp(r'[,.;\n]|and\b')).first.trim();
        if (clean.length >= 4 &&
            !clean.toLowerCase().contains('pain') &&
            !_isNegated(clean, lower)) {
          hits.add(_formatTitle(clean));
        }
      }
    }

    return hits.take(4).toList();
  }

  List<NotedMedicine> _extractMedicines(String lower) {
    final results = <NotedMedicine>[];

    for (final entry in _commonMedications.entries) {
      final drug = entry.key;
      if (lower.contains(drug)) {
        final defaultSpec = entry.value;

        // Try extracting specified dosage near the medicine name
        final nearPattern = RegExp(
          RegExp.escape(drug) +
              r'(?:\s+(\d+(?:\.\d+)?\s*(?:mg|gm|g|mcg|ml|iu|units?)))?' +
              r'(?:\s+([a-z0-9\s]{1,30}))?',
        );
        final m = nearPattern.firstMatch(lower);

        String dosage = defaultSpec.defaultDose;
        String instructions = defaultSpec.defaultFreq;

        if (m != null) {
          final matchedDose = m.group(1)?.trim();
          if (matchedDose != null && matchedDose.isNotEmpty) {
            dosage = matchedDose.toUpperCase();
          }

          // Check if frequency or instruction is stated
          if (lower.contains('twice daily') || lower.contains('twice a day') || lower.contains('bd')) {
            instructions = '1 tab BD after food';
          } else if (lower.contains('thrice daily') || lower.contains('three times') || lower.contains('tds')) {
            instructions = '1 tab TDS after food';
          } else if (lower.contains('once daily') || lower.contains('once a day') || lower.contains('od')) {
            instructions = '1 tab OD';
          } else if (lower.contains('before breakfast') || lower.contains('empty stomach')) {
            instructions = 'Before food in morning';
          } else if (lower.contains('at bedtime') || lower.contains('at night') || lower.contains('hs')) {
            instructions = '1 tab at bedtime';
          }
        }

        results.add(
          NotedMedicine(
            name: _formatTitle(drug),
            dosage: dosage,
            instructions: instructions,
          ),
        );
      }
    }

    return results;
  }

  String? _extractAdvice(String text, String lower) {
    final advicePatterns = [
      RegExp(r'\b(avoid\s+[^.,;\n]+)', caseSensitive: false),
      RegExp(r'\b(apply\s+(?:ice|hot|heat|cold|pack|fermentation)[^.,;\n]*)', caseSensitive: false),
      RegExp(r'\b(start\s+(?:gentle|physiotherapy|exercises|walking|stretching)[^.,;\n]*)', caseSensitive: false),
      RegExp(r'\b(maintain\s+(?:good posture|ergonomics|hydration)[^.,;\n]*)', caseSensitive: false),
      RegExp(r'\b(take\s+(?:adequate rest|plenty of fluids)[^.,;\n]*)', caseSensitive: false),
    ];

    final pieces = <String>[];
    for (final p in advicePatterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        final val = m.group(1)?.trim();
        if (val != null && val.isNotEmpty) {
          pieces.add(_formatSentence(val));
        }
      }
    }

    if (pieces.isNotEmpty) {
      return pieces.join('. ');
    }

    return null;
  }

  Map<String, String?> _extractVitals(String lower) {
    String? bp;
    String? temp;
    String? pulse;

    // Blood pressure: 120/80, 130 over 80, BP 120 80
    final bpRegex = RegExp(
      r'\b(?:bp|blood pressure)\s*(?:is|was|of|:)?\s*(\d{2,3})\s*(?:[\/\-]|over|by|\s+)\s*(\d{2,3})\b',
    );
    final bpMatch = bpRegex.firstMatch(lower);
    if (bpMatch != null) {
      bp = '${bpMatch.group(1)}/${bpMatch.group(2)} mmHg';
    }

    // Temperature: 98.6 F, 99.4, 101 degrees
    final tempRegex = RegExp(
      r'\b(?:temp|temperature|fever)\s*(?:is|was|of|:)?\s*(\d{2,3}(?:\.\d+)?)\s*(?:f|c|deg|degree|degrees|fahrenheit)?\b',
    );
    final tempMatch = tempRegex.firstMatch(lower);
    if (tempMatch != null) {
      final val = tempMatch.group(1);
      temp = '$val °F';
    }

    // Pulse: 72 bpm, 80 pulse, heart rate 78
    final pulseRegex = RegExp(
      r'\b(?:pulse|heart rate|hr|pulse rate)\s*(?:is|was|of|:)?\s*(\d{2,3})\s*(?:bpm|per min|beats)?\b',
    );
    final pulseMatch = pulseRegex.firstMatch(lower);
    if (pulseMatch != null) {
      pulse = '${pulseMatch.group(1)} bpm';
    }

    return {'bp': bp, 'temp': temp, 'pulse': pulse};
  }

  Map<String, String?> _extractPain(String lower, [_DialogueContext? context]) {
    String? now;
    String? worst;
    String? location;
    String? nature;

    int? wordToDigit(String w) {
      const map = {
        'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
        'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
      };
      return int.tryParse(w) ?? map[w.toLowerCase()];
    }

    // Current pain NPRS 0-10
    final painNowRegex = RegExp(
      r'\b(?:pain(?:\s+now|\s+today|\s+currently|\s+score)?|nprs|vas|rate(?:\s+it)?|say|give\s+it)\s*(?:is|was|at|around)?\s*(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)\s*(?:out of 10|\/10|on 10|out of rick ten)?\b',
    );
    final nowMatch = painNowRegex.firstMatch(lower);
    if (nowMatch != null) {
      final score = wordToDigit(nowMatch.group(1) ?? '');
      if (score != null && score <= 10) {
        now = '$score/10';
      }
    }

    // Direct score fallback: "7 on 10", "7 out of 10", "7/10"
    if (now == null) {
      final directScoreRegex = RegExp(
        r'\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)\s*(?:out of 10|\/10|on 10)\b',
      );
      final dm = directScoreRegex.firstMatch(lower);
      if (dm != null) {
        final score = wordToDigit(dm.group(1) ?? '');
        if (score != null && score <= 10) {
          now = '$score/10';
        }
      }
    }

    now ??= context?.painScore;

    // Worst pain
    final painWorstRegex = RegExp(
      r'\b(?:worst|maximum|peak|highest)(?:\s+pain)?\s*(?:is|was|reached|at)?\s*(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten)\b',
    );
    final worstMatch = painWorstRegex.firstMatch(lower);
    if (worstMatch != null) {
      final score = wordToDigit(worstMatch.group(1) ?? '');
      if (score != null && score <= 10) {
        worst = '$score/10';
      }
    }

    // Pain location
    final locations = [
      'right shoulder',
      'left shoulder',
      'cervical spine',
      'neck',
      'lower back',
      'lumbar spine',
      'right knee',
      'left knee',
      'bilateral knees',
      'right ankle',
      'left ankle',
      'right hip',
      'left hip',
      'right wrist',
      'left wrist',
      'right elbow',
      'left elbow',
      'right side',
      'left side',
      'right flank',
      'left flank',
      'groin',
    ];
    for (final loc in locations) {
      if (lower.contains(loc)) {
        location = _formatTitle(loc);
        break;
      }
    }

    // Pain nature
    final natures = [
      'sharp shooting pain',
      'throbbing pain',
      'dull ache',
      'burning sensation',
      'stabbing pain',
      'radiating pain',
      'constant ache',
      'pins and needles',
      'very severe pain',
      'severe pain',
    ];
    for (final nat in natures) {
      if (lower.contains(nat)) {
        nature = _formatSentence(nat);
        break;
      }
    }

    location ??= context?.location;

    return {
      'painNow': now,
      'painWorst': worst,
      'painLocation': location,
      'painNature': nature,
    };
  }

  DateTime? _extractFollowUp(String lower) {
    // "follow up after 5 days", "review in 1 week", "see me next monday"
    final daysMatch = RegExp(r'\b(?:follow\s*up|review|see me|come back)\s*(?:after|in)?\s*(\d+)\s*days?\b').firstMatch(lower);
    if (daysMatch != null) {
      final d = int.tryParse(daysMatch.group(1) ?? '');
      if (d != null) {
        return DateTime.now().add(Duration(days: d));
      }
    }

    final weeksMatch = RegExp(r'\b(?:follow\s*up|review|see me|come back)\s*(?:after|in)?\s*(\d+)\s*weeks?\b').firstMatch(lower);
    if (weeksMatch != null) {
      final w = int.tryParse(weeksMatch.group(1) ?? '');
      if (w != null) {
        return DateTime.now().add(Duration(days: w * 7));
      }
    }

    return null;
  }

  static String _formatTitle(String s) {
    return s.trim().split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  static String _formatSentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t[0].toUpperCase() + t.substring(1);
  }
}
