import 'dart:math' as math;

import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Result of matching a spoken name against the doctor's patients.
class NameMatch {
  const NameMatch(this.best, this.score, this.runnerUp, [this.tied = const []]);

  final Patient? best;
  final double score;
  final Patient? runnerUp;

  /// Everyone within 0.1 of the best, best first: two "Rahul Patel"s, or
  /// "Rahul" matching Rahul Patel and Rahul Shah.
  final List<Patient> tied;

  /// Confident enough to act without asking.
  bool get isSure => best != null && score >= 0.7 && runnerUp == null;
}

/// Matches misheard names by how they sound: "sohom" finds Soham, "raul
/// patel" finds Rahul Patel. The recogniser mishears names rather than
/// paraphrasing them, so spelling-by-sound beats meaning here.
NameMatch matchPatient(String spoken, List<Patient> patients) {
  final said = spoken
      .toLowerCase()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  if (said.isEmpty || patients.isEmpty) return const NameMatch(null, 0, null);

  final scored = [for (final p in patients) (p, _score(said, p))]
    ..sort((a, b) => b.$2.compareTo(a.$2));

  final best = scored.first;
  // Patients within 0.1 of each other: ask rather than guess.
  final tied = [
    for (final (p, s) in scored)
      if (s > best.$2 - 0.1) p,
  ];
  final close = tied.length > 1 ? tied[1] : null;
  return NameMatch(best.$1, best.$2, close, tied);
}

double _score(List<String> said, Patient p) {
  final parts = p.fullName.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (parts.isEmpty) return 0;

  // Whole name against whole phrase ("ordered good" vs "boridkar" too).
  final whole = _sim(said.join(), parts.join());

  // Each part of the patient's name against its best spoken word or pair.
  final pieces = [
    ...said,
    for (var i = 0; i + 1 < said.length; i++) said[i] + said[i + 1],
  ];
  var sum = 0.0;
  for (final part in parts) {
    sum += pieces.map((w) => _sim(w, part)).reduce(math.max);
  }
  var perPart = sum / parts.length;

  // Only a first name was said ("open rahul"): fine, but less certain.
  if (said.length == 1) {
    perPart = math.max(perPart, _sim(said.first, parts.first) * 0.85);
  }
  return math.max(whole, perPart);
}

/// Sound-alike similarity, 0–1: half the spelling key, half the consonant
/// skeleton (vowels are what speech recognisers get wrong most).
double _sim(String a, String b) {
  final ka = _key(a), kb = _key(b);
  if (ka.isEmpty || kb.isEmpty) return 0;
  return 0.5 * _ratio(ka, kb) + 0.5 * _ratio(_skeleton(ka), _skeleton(kb));
}

/// Folds spellings that sound the same in Indian names.
String _key(String s) {
  var k = s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  const pairs = [
    ('ph', 'f'),
    ('sh', 's'),
    ('th', 't'),
    ('dh', 'd'),
    ('bh', 'b'),
    ('kh', 'k'),
    ('gh', 'g'),
    ('jh', 'j'),
    ('ck', 'k'),
    ('q', 'k'),
    ('x', 'ks'),
    ('z', 'j'),
    ('w', 'v'),
    ('ee', 'i'),
    ('oo', 'u'),
    ('aa', 'a'),
    ('y', 'i'),
  ];
  for (final (from, to) in pairs) {
    k = k.replaceAll(from, to);
  }
  if (k.length > 1) k = k[0] + k.substring(1).replaceAll('h', '');
  return k.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
}

String _skeleton(String k) =>
    k.isEmpty ? k : k[0] + k.substring(1).replaceAll(RegExp('[aeiou]'), '');

double _ratio(String a, String b) {
  final d = _levenshtein(a, b);
  return 1 - d / math.max(a.length, b.length);
}

int _levenshtein(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = math.min(
        math.min(cur[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    prev = cur;
  }
  return prev[b.length];
}
