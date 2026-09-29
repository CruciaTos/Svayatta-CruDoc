/// Content-aware medical conditions engine and clinical note formatter.
///
/// Ensures only actual medical conditions, diagnoses, and clinical terms
/// are extracted into the Conditions field (never conversational speech like
/// "he is", "serving", "my"), and formats clinical notes neatly into bullet points.
library;

/// Comprehensive medical conditions dictionary mapping colloquial and clinical
/// terms to standardized, professional medical diagnosis labels.
const Map<String, String> kConditionLexicon = {
  // Neurological & Headaches
  'migraine': 'Migraine',
  'migraines': 'Migraine',
  'chronic migraine': 'Migraine',
  'hemicrania': 'Migraine',
  'tension headache': 'Tension headache',
  'cluster headache': 'Cluster headache',
  'headache': 'Chronic headache',
  'epilepsy': 'Epilepsy',
  'epileptic': 'Epilepsy',
  'seizure': 'Seizure disorder',
  'seizures': 'Seizure disorder',
  'convulsions': 'Seizure disorder',
  'stroke': 'Stroke',
  'cva': 'Stroke',
  'tia': 'Transient ischaemic attack',
  'mini stroke': 'Transient ischaemic attack',
  'parkinsons': "Parkinson's disease",
  'parkinson': "Parkinson's disease",
  'alzheimers': "Alzheimer's disease",
  'alzheimer': "Alzheimer's disease",
  'dementia': 'Dementia',
  'neuropathy': 'Neuropathy',
  'peripheral neuropathy': 'Peripheral neuropathy',
  'diabetic neuropathy': 'Diabetic neuropathy',
  'vertigo': 'Vertigo',
  'dizziness': 'Vertigo',
  'multiple sclerosis': 'Multiple sclerosis',
  'ms': 'Multiple sclerosis',
  'bell palsy': "Bell's palsy",
  'bells palsy': "Bell's palsy",

  // Cardiovascular
  'hypertension': 'Hypertension',
  'hypertensive': 'Hypertension',
  'high blood pressure': 'Hypertension',
  'high bp': 'Hypertension',
  'bp': 'Hypertension',
  'hypotension': 'Hypotension',
  'low blood pressure': 'Hypotension',
  'low bp': 'Hypotension',
  'cardiac': 'Heart disease',
  'heart disease': 'Heart disease',
  'heart problem': 'Heart disease',
  'heart condition': 'Heart disease',
  'coronary artery disease': 'Coronary artery disease',
  'cad': 'Coronary artery disease',
  'arrhythmia': 'Arrhythmia',
  'palpitations': 'Arrhythmia',
  'heart attack': 'Myocardial infarction',
  'myocardial infarction': 'Myocardial infarction',
  'angina': 'Angina',
  'heart failure': 'Heart failure',
  'chf': 'Heart failure',
  'pacemaker': 'Cardiac pacemaker',
  'hyperlipidemia': 'Hyperlipidemia',
  'high cholesterol': 'High cholesterol',
  'cholesterol': 'High cholesterol',
  'dyslipidemia': 'Dyslipidemia',
  'atherosclerosis': 'Atherosclerosis',
  'varicose veins': 'Varicose veins',

  // Endocrine & Metabolic
  'diabetes': 'Diabetes',
  'diabetic': 'Diabetes',
  'sugar': 'Diabetes',
  'type 1 diabetes': 'Type 1 Diabetes',
  'type 2 diabetes': 'Type 2 Diabetes',
  'gestational diabetes': 'Gestational Diabetes',
  'prediabetes': 'Prediabetes',
  'prediabetic': 'Prediabetes',
  'thyroid': 'Thyroid disorder',
  'hypothyroid': 'Hypothyroidism',
  'hypothyroidism': 'Hypothyroidism',
  'hyperthyroid': 'Hyperthyroidism',
  'hyperthyroidism': 'Hyperthyroidism',
  'goitre': 'Goitre',
  'goiter': 'Goitre',
  'pcos': 'PCOS',
  'pcod': 'PCOS',
  'polycystic ovary': 'PCOS',
  'obese': 'Obesity',
  'obesity': 'Obesity',
  'overweight': 'Overweight',
  'gout': 'Gout',
  'hyperuricemia': 'Gout',
  'vitamin d deficiency': 'Vitamin D deficiency',
  'vitamin b12 deficiency': 'Vitamin B12 deficiency',
  'osteoporosis': 'Osteoporosis',
  'osteopenia': 'Osteopenia',

  // Respiratory & ENT
  'asthma': 'Asthma',
  'asthmatic': 'Asthma',
  'bronchitis': 'Bronchitis',
  'chronic bronchitis': 'Chronic bronchitis',
  'copd': 'COPD',
  'emphysema': 'COPD',
  'pneumonia': 'Pneumonia',
  'tuberculosis': 'Tuberculosis',
  'tb': 'Tuberculosis',
  'sinusitis': 'Sinusitis',
  'sinus': 'Sinusitis',
  'sinus infection': 'Sinusitis',
  'allergic rhinitis': 'Allergic rhinitis',
  'rhinitis': 'Rhinitis',
  'hay fever': 'Allergic rhinitis',
  'pharyngitis': 'Pharyngitis',
  'tonsillitis': 'Tonsillitis',
  'sore throat': 'Pharyngitis',
  'sleep apnea': 'Sleep apnea',
  'osa': 'Sleep apnea',
  'deviated nasal septum': 'Deviated nasal septum',
  'dns': 'Deviated nasal septum',

  // Dental & Oral
  'caries': 'Dental caries',
  'dental caries': 'Dental caries',
  'cavity': 'Dental caries',
  'cavities': 'Dental caries',
  'tooth decay': 'Dental caries',
  'decay': 'Dental caries',
  'gingivitis': 'Gingivitis',
  'gum bleeding': 'Gingivitis',
  'bleeding gums': 'Gingivitis',
  'periodontitis': 'Periodontitis',
  'pyorrhea': 'Periodontitis',
  'periodontal disease': 'Periodontitis',
  'pulpitis': 'Pulpitis',
  'abscess': 'Dental abscess',
  'dental abscess': 'Dental abscess',
  'tooth abscess': 'Dental abscess',
  'periapical abscess': 'Dental abscess',
  'malocclusion': 'Malocclusion',
  'crowding': 'Dental crowding',
  'bruxism': 'Bruxism',
  'teeth grinding': 'Bruxism',
  'oral ulcer': 'Oral ulcer',
  'aphthous ulcer': 'Aphthous ulcer',
  'mouth ulcer': 'Oral ulcer',
  'canker sore': 'Oral ulcer',
  'pericoronitis': 'Pericoronitis',
  'tmj': 'TMJ disorder',
  'tmj disorder': 'TMJ disorder',
  'jaw pain': 'TMJ disorder',
  'leukoplakia': 'Leukoplakia',
  'enamel erosion': 'Enamel erosion',
  'tooth wear': 'Tooth wear',
  'attrition': 'Dental attrition',
  'halitosis': 'Halitosis',
  'bad breath': 'Halitosis',
  'fluorosis': 'Dental fluorosis',
  'impacted tooth': 'Impacted tooth',
  'wisdom tooth pain': 'Impacted tooth',

  // Gastrointestinal & Hepatic
  'gerd': 'GERD',
  'acid reflux': 'GERD',
  'reflux': 'GERD',
  'acidity': 'Gastritis',
  'gastritis': 'Gastritis',
  'heartburn': 'GERD',
  'peptic ulcer': 'Peptic ulcer',
  'stomach ulcer': 'Peptic ulcer',
  'ulcer': 'Peptic ulcer',
  'ibs': 'IBS',
  'irritable bowel': 'IBS',
  'ibd': 'IBD',
  'crohns': "Crohn's disease",
  'ulcerative colitis': 'Ulcerative colitis',
  'fatty liver': 'Fatty liver',
  'nafld': 'Fatty liver',
  'hepatitis': 'Hepatitis',
  'hepatitis b': 'Hepatitis B',
  'hepatitis c': 'Hepatitis C',
  'cirrhosis': 'Cirrhosis',
  'gallstones': 'Gallstones',
  'cholelithiasis': 'Gallstones',
  'piles': 'Hemorrhoids',
  'hemorrhoids': 'Hemorrhoids',
  'constipation': 'Chronic constipation',
  'chronic constipation': 'Chronic constipation',

  // Musculoskeletal & Rheumatology
  'arthritis': 'Arthritis',
  'osteoarthritis': 'Osteoarthritis',
  'rheumatoid arthritis': 'Rheumatoid arthritis',
  'ra': 'Rheumatoid arthritis',
  'spondylosis': 'Spondylosis',
  'cervical spondylosis': 'Cervical spondylosis',
  'lumbar spondylosis': 'Lumbar spondylosis',
  'spondylitis': 'Spondylitis',
  'ankylosing spondylitis': 'Ankylosing spondylitis',
  'sciatica': 'Sciatica',
  'back pain': 'Chronic back pain',
  'lower back pain': 'Low back pain',
  'frozen shoulder': 'Frozen shoulder',
  'fibromyalgia': 'Fibromyalgia',
  'tendonitis': 'Tendonitis',
  'plantar fasciitis': 'Plantar fasciitis',

  // Renal & Urological
  'kidney stone': 'Kidney stones',
  'kidney stones': 'Kidney stones',
  'renal calculi': 'Kidney stones',
  'nephrolithiasis': 'Kidney stones',
  'chronic kidney disease': 'CKD',
  'ckd': 'CKD',
  'renal failure': 'Renal disease',
  'uti': 'UTI',
  'urinary tract infection': 'UTI',
  'bph': 'BPH',
  'prostate enlargement': 'BPH',

  // Dermatology & Allergy
  'eczema': 'Eczema',
  'atopic dermatitis': 'Eczema',
  'psoriasis': 'Psoriasis',
  'dermatitis': 'Dermatitis',
  'contact dermatitis': 'Contact dermatitis',
  'acne': 'Acne vulgaris',
  'urticaria': 'Urticaria',
  'hives': 'Urticaria',
  'vitiligo': 'Vitiligo',
  'fungal infection': 'Fungal infection',
  'tinea': 'Fungal infection',
  'ringworm': 'Fungal infection',
  'alopecia': 'Alopecia',
  'hair fall': 'Alopecia',
  'scabies': 'Scabies',

  // Hematology & Infectious
  'anemia': 'Anaemia',
  'anaemia': 'Anaemia',
  'anemic': 'Anaemia',
  'iron deficiency': 'Iron deficiency anaemia',
  'thalassemia': 'Thalassemia',
  'bleeding disorder': 'Bleeding disorder',
  'hemophilia': 'Hemophilia',
  'dengue': 'Dengue fever',
  'malaria': 'Malaria',
  'typhoid': 'Typhoid fever',
  'covid': 'COVID-19',
  'covid 19': 'COVID-19',
  'coronavirus': 'COVID-19',
  'hiv': 'HIV',
  'aids': 'HIV/AIDS',

  // Psychiatry & Mood
  'anxiety': 'Anxiety disorder',
  'generalized anxiety': 'Anxiety disorder',
  'depression': 'Depression',
  'major depression': 'Depression',
  'insomnia': 'Insomnia',
  'panic disorder': 'Panic disorder',
  'panic attacks': 'Panic disorder',
  'bipolar': 'Bipolar disorder',
  'adhd': 'ADHD',
  'ocd': 'OCD',

  // General & Lifestyle
  'cancer': 'Cancer',
  'carcinoma': 'Cancer',
  'tumor': 'Tumor',
  'chemotherapy': 'Undergoing chemotherapy',
  'smoker': 'Tobacco smoker',
  'smoking': 'Tobacco smoker',
  'tobacco chewer': 'Tobacco user',
  'alcoholism': 'Alcohol dependence',
  'pregnant': 'Pregnancy',
  'pregnancy': 'Pregnancy',
  'lactating': 'Lactating',
  'breastfeeding': 'Lactating',
};

/// Multi-word conditions sorted by word count descending, so longer phrases
/// match before shorter substrings (e.g. "type 2 diabetes" before "diabetes").
final List<String> kMultiWordConditions = () {
  final list = kConditionLexicon.keys.where((k) => k.contains(' ')).toList();
  list.sort((a, b) => b.length.compareTo(a.length));
  return list;
}();

/// Non-condition conversational words and pronouns that must NEVER be
/// interpreted as a medical condition.
const Set<String> kJunkConditionWords = {
  'he',
  'she',
  'they',
  'i',
  'we',
  'you',
  'it',
  'his',
  'her',
  'their',
  'my',
  'your',
  'its',
  'is',
  'are',
  'was',
  'were',
  'am',
  'be',
  'been',
  'being',
  'has',
  'have',
  'had',
  'having',
  'suffering',
  'suffers',
  'serving',
  'serves',
  'diagnosed',
  'diagnosis',
  'condition',
  'conditions',
  'patient',
  'patients',
  'case',
  'known',
  'from',
  'with',
  'of',
  'in',
  'on',
  'at',
  'to',
  'for',
  'by',
  'a',
  'an',
  'the',
  'this',
  'that',
  'these',
  'those',
  'and',
  'or',
  'also',
  'plus',
  'but',
  'so',
  'add',
  'added',
  'put',
  'enter',
  'write',
  'say',
  'saying',
  'mild',
  'severe',
  'acute',
  'chronic',
  'moderate',
  'very',
  'much',
  'some',
  'lot',
  'lots',
  'yes',
  'no',
  'not',
  'none',
  'nah',
};

/// Content-aware medical condition extractor.
///
/// Scans [tokens] or raw text, identifies genuine clinical conditions,
/// maps them to canonical diagnosis names, and guarantees zero non-medical
/// noise or conversational phrases (like "he serving", "he is", "my") get added.
List<String> extractMedicalConditions(
  List<String> tokens, {
  int start = 0,
  int? end,
}) {
  final stop = end ?? tokens.length;
  if (start >= stop) return const [];

  final subTokens = tokens.sublist(start, stop);
  final matched = <String>[];
  final consumedTokenIndices = <int>{};

  // 1. First pass: Match multi-word phrases (e.g. "high blood pressure", "type 2 diabetes")
  for (final phrase in kMultiWordConditions) {
    final phraseWords = phrase.split(' ');
    final phraseLen = phraseWords.length;
    for (var i = 0; i <= subTokens.length - phraseLen; i++) {
      if (consumedTokenIndices.contains(i)) continue;
      var matches = true;
      for (var j = 0; j < phraseLen; j++) {
        if (subTokens[i + j] != phraseWords[j]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        final canonical = kConditionLexicon[phrase]!;
        if (!matched.contains(canonical)) {
          matched.add(canonical);
        }
        for (var j = 0; j < phraseLen; j++) {
          consumedTokenIndices.add(i + j);
        }
      }
    }
  }

  // 2. Second pass: Match single-word condition terms
  for (var i = 0; i < subTokens.length; i++) {
    if (consumedTokenIndices.contains(i)) continue;
    final word = subTokens[i];

    // Check direct match in lexicon
    final canonical = kConditionLexicon[word];
    if (canonical != null) {
      if (!matched.contains(canonical)) {
        matched.add(canonical);
      }
      consumedTokenIndices.add(i);
      continue;
    }

    // Special clinical suffix rules (e.g. medical terms ending in -itis, -osis, -opathy)
    // Only accept if at least 5 chars and NOT in stop words
    if (word.length >= 5 && !kJunkConditionWords.contains(word)) {
      if (word.endsWith('itis') ||
          word.endsWith('osis') ||
          word.endsWith('opathy') ||
          word.endsWith('algia') ||
          word.endsWith('emia') ||
          word.endsWith('aemia')) {
        final title = word[0].toUpperCase() + word.substring(1);
        if (!matched.contains(title)) {
          matched.add(title);
        }
        consumedTokenIndices.add(i);
      }
    }
  }

  return matched;
}

/// Checks whether a note phrase is an incomplete fragment
/// (e.g., "Has an", "He has", "Allergic to", "Patient is", etc.).
bool isIncompleteNoteFragment(String s) {
  final trimmed = s
      .trim()
      .replaceAll(RegExp(r'^[•\s*\\-]+|[,\s.:;•*\\-]+$'), '')
      .trim();
  if (trimmed.isEmpty) return true;
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length < 2) return true;
  // If it ends with a dangling preposition / article / conjunction / auxiliary:
  if (RegExp(
    r'\b(?:an|a|the|for|to|of|in|on|at|with|from|as|and|or|is|are|was|were|has|have|had|that)\s*$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return true;
  }
  // If it consists solely of pronouns and auxiliaries (e.g. "he is", "he has an")
  if (RegExp(
    r'^(?:he|she|they|patient|the\s+patient)\s+(?:is|has|was|had|an|a)\s*$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return true;
  }
  return false;
}

/// Splits compound spoken clinical observations into distinct statements
/// (e.g., "Has allergy for cucumbers and also he is sensitive to light"
///  -> ["Has allergy for cucumbers", "sensitive to light"]).
List<String> splitNoteObservations(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return [];

  final splitRegex = RegExp(
    r'(?:[;]|\.\s+'
    r'|\s*,\s*(?:and\s+)?also\s+'
    r'|\s+and\s+also\s+(?:he\s+is\s+|she\s+is\s+|patient\s+is\s+|he\s+has\s+|she\s+has\s+|they\s+are\s+)?'
    r'|\s+as\s+well\s+as\s+'
    r'|\s+and\s+(?:he\s+is|she\s+is|patient\s+is|they\s+are|he\s+has|she\s+has)\s+'
    r'|\s+also\s+(?:he\s+is|she\s+is|patient\s+is|sensitive\s+to|allergic\s+to|has\s+|takes\s+|prefers\s+)'
    r'|\s*,\s*plus\s+)',
    caseSensitive: false,
  );

  final parts = trimmed.split(splitRegex);
  return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}

/// Cleans spoken note phrases by stripping conversational speech wrappers
/// (e.g., "Add that he has allergies for apple seeds" -> "Has allergy for apple seeds").
String cleanNoteText(String raw) {
  var s = raw.trim();
  // Strip trailing/leading punctuation
  s = s.replaceAll(RegExp(r'^[,\s.:;•*\\-]+|[,\s.:;•*\\-]+$'), '').trim();

  // Strip command / conversational prefixes:
  // "add that he has", "add a note that", "note: add that", "in notes add that", etc.
  final prefixRegex = RegExp(
    r'^(?:please\s+)?(?:also\s+)?(?:add|put|write|make|take|enter|dictate)?\s*'
    r'(?:a\s+)?(?:note|notes|remark|remarks|comment|comments)?\s*'
    r'(?:that|to|in|into)?\s*(?:the\s+)?(?:notes?|file|chart|record)?\s*'
    r'(?:that|:|,\s*)?\s*'
    r'(?:the\s+patient\s+|patient\s+|he\s+|she\s+|they\s+)?'
    r'(?:is\s+|has\s+|are\s+)?',
    caseSensitive: false,
  );
  s = s.replaceFirst(prefixRegex, '').trim();

  // Strip optional leading "that", "he is", "she is", "patient is", etc.
  s = s
      .replaceFirst(
        RegExp(
          r'^(?:that\s+)?(?:the\s+patient\s+|patient\s+|he\s+|she\s+|they\s+)?(?:is\s+|has\s+|are\s+)?',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  // Allergy phrasing normalizations:
  // "allergies for apple seeds" -> "Has allergy for apple seeds"
  // "allergy for cucumbers" -> "Has allergy for cucumbers"
  // "an allergy for cucumbers" -> "Has allergy for cucumbers"
  // "allergies to penicillin" -> "Has allergy to penicillin"
  if (RegExp(
    r'^(?:has\s+)?(?:an\s+)?(?:allergies|allergy)\s+(?:for|to)\s+',
    caseSensitive: false,
  ).hasMatch(s)) {
    s = s.replaceFirst(
      RegExp(
        r'^(?:has\s+)?(?:an\s+)?(?:allergies|allergy)\s+',
        caseSensitive: false,
      ),
      'Has allergy ',
    );
  } else if (RegExp(r'^allergic\s+to\s+', caseSensitive: false).hasMatch(s)) {
    s = s.replaceFirst(
      RegExp(r'^allergic\s+to\s+', caseSensitive: false),
      'Allergic to ',
    );
  }

  // Capitalize first character
  if (s.isNotEmpty) {
    s = s[0].toUpperCase() + s.substring(1);
  }

  // Reject incomplete fragments
  if (isIncompleteNoteFragment(s)) {
    return '';
  }

  return s;
}

/// Cleans and formats raw note text into one or more clean bullet points,
/// splitting compound observations and rejecting incomplete fragments.
List<String> formatNoteBulletLines(String note) {
  final parts = splitNoteObservations(note);
  final bullets = <String>[];
  for (final part in parts) {
    final clean = cleanNoteText(part);
    if (clean.isNotEmpty && !isIncompleteNoteFragment(clean)) {
      final b = clean.startsWith('•') ? clean : '• $clean';
      if (!bullets.any(
        (existing) => existing.toLowerCase() == b.toLowerCase(),
      )) {
        bullets.add(b);
      }
    }
  }
  return bullets;
}

/// Formats a note or compound note into clean bullet point lines (`• Note`).
String formatBulletNote(String note) {
  final lines = formatNoteBulletLines(note);
  return lines.join('\n');
}

/// Formats and joins notes into bullet points one by one.
String joinBulletNotes(String? existing, String newNote) {
  final newBullets = formatNoteBulletLines(newNote);
  if (newBullets.isEmpty) return existing ?? '';

  if (existing == null || existing.trim().isEmpty) {
    return newBullets.join('\n');
  }

  // Split existing lines and ensure all lines have bullets
  final lines = existing
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !isIncompleteNoteFragment(l))
      .map((l) => l.startsWith('•') ? l : '• $l')
      .toList();

  for (final bullet in newBullets) {
    if (!lines.any((l) => l.toLowerCase() == bullet.toLowerCase())) {
      lines.add(bullet);
    }
  }

  return lines.join('\n');
}
