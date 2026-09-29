import 'package:flutter/material.dart' show TimeOfDay;

/// What the doctor is asking for. Keyword rules, not a model: the demo has
/// four commands, and rules are instant, predictable and easy to tune.
enum VoiceIntent {
  none,
  openPatient,
  addPatient,
  addAppointment,
  reschedule,
  confirm,
  cancel,

  /// Change an existing patient's details ("change his phone to…").
  editPatient,

  /// Call off an appointment ("cancel Rahul's appointment").
  cancelAppointment,

  /// Today's visit is over ("mark Rahul as done").
  markDone,

  /// They didn't come ("Rahul didn't show up").
  markMissed,

  /// Money received ("Rahul paid 500").
  recordPayment,

  /// A line for the patient's notes, without opening a form.
  addNote,
}

/// One parsed utterance. Every field is optional: partial speech fills in
/// what it can, and later speech fills in the rest.
class VoiceCommand {
  const VoiceCommand({
    required this.intent,
    this.name = '',
    this.corrected = false,
    this.confirmAtEnd = false,
    this.otherNames = const [],
    this.firstName,
    this.lastName,
    this.date,
    this.time,
    this.age,
    this.dateOfBirth,
    this.gender,
    this.phone,
    this.email,
    this.conditions = const [],
    this.notes,
    this.balance,
    this.reason,
    this.durationMinutes,
    this.homeVisit,
    this.address,
    this.sendWhatsApp,
    this.addToQueue,
    this.slot,
    this.phoneEnding,
    this.shiftMinutes,
    this.payment,
  });

  final VoiceIntent intent;

  /// Left-over words that should be a patient name ("rahul patel").
  final String name;

  /// The name came after "no" / "sorry" / "actually": replace, don't keep.
  final bool corrected;

  /// Ended with "…and confirm" / "…book it": fill, then save.
  final bool confirmAtEnd;

  /// More patients booked together ("…and Priya Sharma").
  final List<String> otherNames;

  /// Said explicitly ("first name Soham", "surname Boridkar").
  final String? firstName;
  final String? lastName;

  /// Appointment date and time.
  final DateTime? date;
  final TimeOfDay? time;

  final int? age;
  final DateTime? dateOfBirth;

  /// 'Male', 'Female' or 'Other', matching the patient form's options.
  final String? gender;

  /// Digits only.
  final String? phone;
  final String? email;
  final List<String> conditions;
  final String? notes;
  final double? balance;

  /// Why they're coming ("Root canal", "Tooth pain").
  final String? reason;
  final int? durationMinutes;

  /// true = home visit, false = in the clinic, null = not said.
  final bool? homeVisit;
  final String? address;
  final bool? sendWhatsApp;
  final bool? addToQueue;

  /// No exact time, but a part of the day or "the next free slot":
  /// 'morning', 'afternoon', 'evening' or 'any'. The app picks a free time.
  final String? slot;

  /// "Ending 3210", "last digits 7788": tells same-named patients apart.
  final String? phoneEnding;

  /// "Push it by an hour" (+60), "30 minutes earlier" (-30).
  final int? shiftMinutes;

  /// "Paid 500", "received 800".
  final double? payment;

  static VoiceCommand parse(String text, DateTime now) {
    final (rest, email) = _extractEmail(text.toLowerCase());
    // "Note for Rahul: prefers evenings", "add a note to his file,
    // allergic to penicillin": after the colon or comma is the note;
    // before it, whose note.
    final split = RegExp(
      r'\b(note|notes|remark|remarks|comment|comments)\b([^:,]*)[:,]\s*(.+)$',
    ).firstMatch(rest);
    final tokens = tokenize(rest);
    if (split == null) return _Parser(tokens, now, email).run();
    final body = split.group(3)!.trim().replaceAll(RegExp(r'[.\s]+$'), '');
    final from = tokenize(
      rest.substring(
        0,
        split.start + split.group(0)!.length - split.group(3)!.length,
      ),
    ).length;
    return _Parser(tokens, now, email, noteFrom: from, noteBody: body).run();
  }
}

// ── Email ───────────────────────────────────────────────────────────────

const _mailDomains =
    'gmail|yahoo|hotmail|outlook|rediffmail|icloud|protonmail|live|ymail';

/// Pulls an email out of [text] before it is split into words: a written
/// one ("soham@gmail.com") or a spoken one after "email" ("soham dot b at
/// the rate gmail dot com"). Returns the text without it.
(String, String?) _extractEmail(String text) {
  final written = RegExp(
    r'[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+',
  ).firstMatch(text);
  if (written != null) {
    final email = written.group(0)!.replaceAll(RegExp(r'\.+$'), '');
    return (text.replaceRange(written.start, written.end, ' , '), email);
  }

  final cue = RegExp(
    r'\b(e-?mail|mail)( id| address)?( is| to)?\b',
  ).firstMatch(text);
  if (cue == null) return (text, null);
  final after = text.substring(cue.end);
  final stop = RegExp(
    r'[,;]|\b(phone|mobile|number|contact|age|aged|born|birth|birthday|dob|'
    r'male|female|note|notes|condition|conditions|address|balance|package|'
    r'and (his|her|their))\b',
  ).firstMatch(after);
  final spoken = stop == null ? after : after.substring(0, stop.start);

  var e = ' ${spoken.trim()} '
      .replaceAll(RegExp(r'\s+at the rate( of)?\s+'), '@')
      .replaceAll(RegExp(r'\s+at\s+'), '@')
      .replaceAll(RegExp(r'\s+dot\s+'), '.')
      .replaceAll(RegExp(r'\s+(underscore|under score)\s+'), '_')
      .replaceAll(RegExp(r'\s+(dash|hyphen)\s+'), '-');
  _digitWords.forEach((w, d) {
    if (w.length > 1) e = e.replaceAll(RegExp('\\b$w\\b'), d);
  });
  e = e.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'\.+$'), '');
  // "gmailcom" → "gmail.com" when "dot" was dropped.
  e = e.replaceAllMapped(
    RegExp('@($_mailDomains)(com|in|coin)\$'),
    (m) => '@${m[1]}.${m[2] == 'coin' ? 'co.in' : m[2]}',
  );
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return (text, null);
  final end = cue.end + (stop?.start ?? after.length);
  return (text.replaceRange(cue.start, end, ' , '), e);
}

/// Close enough to be the same word misheard or spelled differently
/// ("sameer" / "samir"): same first letter, a letter or two apart.
bool soundsAlike(String a, String b) {
  if (a.isEmpty || b.isEmpty || a[0] != b[0] || a.length < 3) return false;
  if (a == b) return true;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final best = cur[j - 1] + 1 < prev[j] + 1 ? cur[j - 1] + 1 : prev[j] + 1;
      cur[j] = best < prev[j - 1] + cost ? best : prev[j - 1] + cost;
    }
    prev = cur;
  }
  return prev[b.length] <= (b.length >= 5 ? 2 : 1);
}

// ── Words ───────────────────────────────────────────────────────────────

/// Lower-case words, with speech-to-text formatting undone: "5pm" →
/// "5 pm", "10.30" → "10:30", "p.m." → "pm", "32-year-old" → "32 year old",
/// "12/03/1990" → "12 03 1990", "5,000" → "5000".
List<String> tokenize(String text) {
  final s = text
      .toLowerCase()
      .replaceAllMapped(
        RegExp(r'(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})'),
        (m) => ' ${m[1]} ${m[2]} ${m[3]} ',
      )
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}${m[2]}')
      .replaceAll(RegExp(r"'s\b"), '')
      .replaceAll("'", '')
      .replaceAllMapped(RegExp(r'(\d)\.(\d)'), (m) => '${m[1]}:${m[2]}')
      // Keep ":" only inside times ("10:30"), not after words ("Note:").
      .replaceAll(RegExp(r'(?<!\d):|:(?!\d)'), ' ')
      .replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^a-z0-9: ]'), ' ');
  final raw = [
    for (final w in s.split(RegExp(r'\s+')))
      if (w.isNotEmpty) ...(_hinglish[w] ?? [w]),
  ];
  // "S O H A M", "B-O-R-I-D-K-A-R": spelled letters become one word.
  // Done before "a m" / "p m" are joined, so "S O H A M" stays whole.
  final spelled = <String>[];
  for (var i = 0; i < raw.length; i++) {
    var j = i;
    while (j < raw.length && RegExp(r'^[a-z]$').hasMatch(raw[j])) {
      j++;
    }
    if (j - i >= 3) {
      final word = raw.sublist(i, j).join();
      // "Samir Joshi, S A M I R": spelling a word just said corrects it
      // rather than adding it again.
      final k = spelled.lastIndexWhere((w) => soundsAlike(w, word));
      if (k >= 0 && spelled.length - k <= 4) {
        spelled[k] = word;
      } else {
        spelled.add(word);
      }
      i = j - 1;
    } else {
      spelled.add(raw[i]);
    }
  }
  final out = <String>[];
  for (var i = 0; i < spelled.length; i++) {
    final w = spelled[i];
    if ((w == 'p' || w == 'a') &&
        i + 1 < spelled.length &&
        spelled[i + 1] == 'm') {
      out.add('${w}m');
      i++;
    } else {
      out.add(w);
    }
  }
  return out;
}

/// Hindi time words doctors mix in ("kal shaam saade paanch baje").
const _hinglish = {
  'aaj': ['today'],
  'kal': ['tomorrow'],
  'parso': ['day', 'after', 'tomorrow'],
  'parson': ['day', 'after', 'tomorrow'],
  'baje': ['o', 'clock'],
  'subah': ['morning'],
  'shaam': ['evening'],
  'dopahar': ['afternoon'],
  'dopehar': ['afternoon'],
  'raat': ['night'],
  'saade': ['half', 'past'],
  'sade': ['half', 'past'],
  'sava': ['quarter', 'past'],
  'paune': ['quarter', 'to'],
  'ek': ['1'],
  'teen': ['3'],
  'paanch': ['5'],
  'panch': ['5'],
  'chhe': ['6'],
  'saat': ['7'],
  'aath': ['8'],
  'nau': ['9'],
  'gyarah': ['11'],
  'barah': ['12'],
};

const _reschedule = {
  'reschedule',
  'rescheduled',
  'move',
  'shift',
  'postpone',
  'prepone',
  'push',
  'change',
  'rebook',
  'delay',
};
const _appointment = {
  'appointment',
  'appointments',
  'appt',
  'book',
  'booking',
  'schedule',
  'slot',
  'consultation',
  'checkup',
  'visit',
};
const _addWords = {'add', 'ad', 'new', 'register', 'create', 'enroll', 'admit'};
const _open = {
  'open',
  'show',
  'pull',
  'view',
  'display',
  'find',
  'search',
  'go',
  'look',
  'details',
  'profile',
  'record',
  'records',
  'file',
  'chart',
};
const _confirm = {
  'confirm',
  'confirmed',
  'save',
  'yes',
  'yeah',
  'yep',
  'done',
  'correct',
  'perfect',
  'submit',
};
const _cancel = {'cancel', 'stop', 'close', 'discard', 'abort', 'nevermind'};
const _confirmish = {
  ..._confirm,
  'go',
  'ahead',
  'book',
  'it',
  'looks',
  'good',
  'thats',
  'ok',
  'okay',
  'and',
  'please',
  'now',
  'all',
  'fine',
  'right',
  'that',
  'is',
  'sure',
  'do',
  'great',
};
const _cancelish = {
  ..._cancel,
  'never',
  'mind',
  'forget',
  'it',
  'scratch',
  'that',
  'no',
  'please',
  'and',
  'leave',
  'thanks',
  'this',
  'the',
  'form',
  'dialog',
  'window',
  'all',
};

const _editVerbs = {'change', 'update', 'edit', 'correct', 'fix', 'set'};

/// Words that name a field on the patient's record.
const _patientFields = {
  'phone',
  'mobile',
  'number',
  'email',
  'mail',
  'age',
  'born',
  'birth',
  'birthday',
  'dob',
  'allergic',
  'allergy',
  'allergies',
  'note',
  'notes',
  'condition',
  'conditions',
  'sex',
  'gender',
  'surname',
  'name',
  'balance',
  'package',
};

/// Words after which the doctor is correcting themselves: the name that
/// follows replaces the one before.
const _corrections = {
  'no',
  'nah',
  'nope',
  'sorry',
  'actually',
  'mean',
  'rather',
};
const _negations = {'no', 'dont', 'not', 'without', 'skip', 'never', 'nt'};

const _weekdays = {
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};

const _months = {
  'january': 1,
  'jan': 1,
  'february': 2,
  'feb': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'aug': 8,
  'september': 9,
  'sept': 9,
  'sep': 9,
  'october': 10,
  'oct': 10,
  'november': 11,
  'nov': 11,
  'december': 12,
  'dec': 12,
};

const _units = {
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};
const _tens = {
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};
const _ordinals = {
  'first': 1,
  'second': 2,
  'third': 3,
  'fourth': 4,
  'fifth': 5,
  'sixth': 6,
  'seventh': 7,
  'eighth': 8,
  'ninth': 9,
  'tenth': 10,
  'eleventh': 11,
  'twelfth': 12,
  'thirteenth': 13,
  'fourteenth': 14,
  'fifteenth': 15,
  'sixteenth': 16,
  'seventeenth': 17,
  'eighteenth': 18,
  'nineteenth': 19,
  'twentieth': 20,
  'thirtieth': 30,
};

/// Spoken phone digits: "nine eight double seven…".
const _digitWords = {
  'zero': '0',
  'oh': '0',
  'o': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
};

const _phoneCues = {'phone', 'mobile', 'number', 'contact', 'cell'};
const _dobCues = {'born', 'birth', 'birthday', 'dob'};
const _reasonCues = {
  'reason',
  'regarding',
  'because',
  'complaint',
  'complaining',
  'purpose',
  'problem',
  'issue',
};
const _noteCues = {'note', 'notes', 'remark', 'remarks', 'comment', 'comments'};
const _allergyCues = {'allergic', 'allergy', 'allergies'};
const _conditionCues = {
  'condition',
  'conditions',
  'diagnosis',
  'diagnosed',
  'suffering',
  'suffers',
  'history',
};
const _balanceCues = {
  'balance',
  'package',
  'advance',
  'deposit',
  'prepaid',
  'credit',
};
const _addressCues = {'address', 'location'};

/// Where a spoken free-text field (notes, address, reason…) ends.
const _fieldCues = {
  ..._phoneCues,
  ..._dobCues,
  ..._reasonCues,
  ..._noteCues,
  ..._allergyCues,
  ..._conditionCues,
  ..._balanceCues,
  ..._addressCues,
  'age',
  'aged',
  'male',
  'female',
  'whatsapp',
  'queue',
  'email',
  'today',
  'tomorrow',
  'tonight',
  'surname',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
};

/// Known conditions, so "she's diabetic with high BP" fills the
/// Conditions field without a cue word.
const _conditionWords = {
  'diabetes': 'Diabetes',
  'diabetic': 'Diabetes',
  'sugar': 'Diabetes',
  'hypertension': 'Hypertension',
  'hypertensive': 'Hypertension',
  'bp': 'Hypertension',
  'asthma': 'Asthma',
  'asthmatic': 'Asthma',
  'thyroid': 'Thyroid',
  'hypothyroid': 'Thyroid',
  'hypothyroidism': 'Thyroid',
  'hyperthyroid': 'Thyroid',
  'cardiac': 'Heart disease',
  'arthritis': 'Arthritis',
  'epilepsy': 'Epilepsy',
  'epileptic': 'Epilepsy',
  'migraine': 'Migraine',
  'pregnant': 'Pregnant',
  'pregnancy': 'Pregnant',
  'anemia': 'Anaemia',
  'anaemia': 'Anaemia',
  'anemic': 'Anaemia',
  'cholesterol': 'High cholesterol',
  'cancer': 'Cancer',
  'hiv': 'HIV',
  'hepatitis': 'Hepatitis',
  'tb': 'Tuberculosis',
  'tuberculosis': 'Tuberculosis',
  'copd': 'COPD',
  'smoker': 'Smoker',
  'pcos': 'PCOS',
  'pcod': 'PCOS',
  'obese': 'Obesity',
  'obesity': 'Obesity',
  'osteoporosis': 'Osteoporosis',
};

/// Visit reasons recognised without a cue word ("…for a root canal").
const _procedures = {
  'cleaning',
  'scaling',
  'polishing',
  'extraction',
  'filling',
  'fillings',
  'rct',
  'canal',
  'crown',
  'bridge',
  'implant',
  'implants',
  'braces',
  'aligner',
  'aligners',
  'veneers',
  'denture',
  'dentures',
  'whitening',
  'dressing',
  'pain',
  'toothache',
  'swelling',
  'bleeding',
  'sensitivity',
  'surgery',
  'review',
  'followup',
  'therapy',
  'physiotherapy',
  'physio',
  'session',
  'ray',
};

/// Words that belong to a reason next to a [_procedures] word.
const _reasonModifiers = {
  'root',
  'tooth',
  'teeth',
  'gum',
  'gums',
  'wisdom',
  'deep',
  'dental',
  'regular',
  'general',
  'knee',
  'back',
  'neck',
  'shoulder',
  'full',
  'mouth',
  'x',
  'follow',
  'up',
  'removal',
  'treatment',
  'check',
};

/// Between two patient names booked together.
const _nameJoins = {'and', 'with', 'along', 'plus', 'aur'};

/// Never part of a name.
const _filler = {
  'a',
  'an',
  'the',
  'for',
  'of',
  'to',
  'at',
  'on',
  'with',
  'named',
  'name',
  'called',
  'patient',
  'patients',
  'please',
  'his',
  'her',
  'him',
  'he',
  'she',
  'their',
  'they',
  'we',
  'our',
  'my',
  'and',
  'is',
  'me',
  'next',
  'this',
  'that',
  'coming',
  'i',
  'want',
  'wants',
  'need',
  'needs',
  'can',
  'could',
  'would',
  'you',
  'up',
  'age',
  'aged',
  'year',
  'years',
  'yr',
  'yrs',
  'old',
  'mr',
  'mrs',
  'ms',
  'miss',
  'doctor',
  'dr',
  'from',
  'it',
  'um',
  'uh',
  'ok',
  'okay',
  'hey',
  'hi',
  'hello',
  'set',
  'make',
  'fix',
  'put',
  'take',
  'get',
  'give',
  'in',
  'clock',
  'o',
  'morning',
  'evening',
  'afternoon',
  'night',
  'tonight',
  'am',
  'pm',
  'today',
  'tomorrow',
  'day',
  'days',
  'week',
  'weeks',
  'after',
  'time',
  'date',
  'same',
  'half',
  'past',
  'quarter',
  'noon',
  'midday',
  'minute',
  'minutes',
  'min',
  'mins',
  'hour',
  'hours',
  'hr',
  'hrs',
  'male',
  'female',
  'man',
  'woman',
  'boy',
  'girl',
  'lady',
  'gentleman',
  'other',
  'sex',
  'gender',
  'home',
  'house',
  'call',
  'clinic',
  'th',
  'st',
  'nd',
  'rd',
  'double',
  'triple',
  'be',
  'there',
  'so',
  'then',
  'just',
  'also',
  'registration',
  'forward',
  'bring',
  'mind',
  'forget',
  'ahead',
  'around',
  'by',
  'till',
  'until',
  'about',
  'will',
  'should',
  'let',
  'lets',
  'us',
  'never',
  'send',
  'sent',
  'whatsapp',
  'message',
  'reminder',
  'sms',
  'queue',
  'dont',
  'not',
  'without',
  'rupees',
  'rs',
  'inr',
  'thousand',
  'hundred',
  'lakh',
  'k',
  'email',
  'mail',
  'id',
  'surname',
  'full',
  'last',
  'along',
  'plus',
  'has',
  'have',
  'got',
  'known',
  'case',
  'are',
  'was',
  'were',
  'right',
  'ka',
  'ki',
  'ke',
  'ko',
  'se',
  'hai',
  'ji',
  'aur',
  'wala',
  'as',
  'update',
  'edit',
  'do',
  'thing',
  'instead',
  'wait',
  'hmm',
  'hm',
  'oh',
  'kindly',
  'quickly',
  'anyway',
  'form',
  'free',
  'available',
  'earliest',
  'asap',
  'whenever',
  'soonest',
  'any',
  'possible',
  'ending',
  'ends',
  'previous',
  'prev',
  'mark',
  'marked',
  'complete',
  'completed',
  'finished',
  'absent',
  'noshow',
  'come',
  'came',
  'didnt',
  'missed',
  'paid',
  'pay',
  'payment',
  'received',
  'receive',
  'collected',
  'collect',
  'later',
  'late',
  'early',
  'sooner',
  'extend',
  'earlier',
  'latest',
  'newest',
  'recent',
  'recently',
  'added',
  'person',
  'seen',
  'saw',
  'see',
  'digits',
  'digit',
  'older',
  'younger',
  'elder',
  'oldest',
  'youngest',
  'when',
  'what',
  'whats',
  'who',
  'whos',
  'where',
  'why',
  'how',
  'much',
  'many',
  'did',
  'does',
  'wali',
  'mein',
  'sir',
  'madam',
  ..._reschedule,
  ..._appointment,
  ..._addWords,
  ..._open,
  ..._confirm,
  ..._cancel,
  ..._corrections,
  ..._phoneCues,
  ..._dobCues,
  ..._reasonCues,
  ..._noteCues,
  ..._allergyCues,
  ..._conditionCues,
  ..._balanceCues,
  ..._addressCues,
};

class _Parser {
  _Parser(this.t, this.now, this._email, {this.noteFrom, this.noteBody});

  /// A note said after a colon or comma, and the word it starts at.
  final int? noteFrom;
  final String? noteBody;

  final List<String> t;
  final DateTime now;
  final String? _email;

  /// Tokens already read as a field.
  final _used = <int>{};

  String? _firstName, _lastName;
  DateTime? _date, _dob;
  TimeOfDay? _time;
  int? _age, _duration;
  String? _gender, _phone, _reason, _address;
  final _notes = <String>[];
  final _conditions = <String>[];
  double? _balance;
  bool? _home, _whatsApp, _queue;
  String? _ending;
  int? _shift;
  double? _paid;
  List<String> _nameList = const [];

  /// "Paid 500", "received ₹800 from him", "collect 300".
  bool _paymentAt(int i) {
    if (!const {
      'paid',
      'pay',
      'payment',
      'received',
      'receive',
      'collected',
      'collect',
    }.contains(t[i])) {
      return false;
    }
    for (var j = i + 1; j <= i + 4 && j < t.length; j++) {
      final a = _amount(j);
      if (a != null && a.$1 >= 10) {
        _paid = a.$1;
        var end = j + a.$2;
        if (const {'rupees', 'rs', 'inr', 'only'}.contains(_at(end))) end++;
        _mark(i, end - i);
        return true;
      }
    }
    return false;
  }

  bool _endingAt(int i) {
    final w = t[i];
    final cue =
        w == 'ending' ||
        w == 'ends' ||
        (w == 'last' &&
            const {
              'digits',
              'digit',
              'four',
              '4',
              'three',
              '3',
            }.contains(_at(i + 1)));
    if (!cue) return false;
    var j = i + 1;
    while (const {
      'with',
      'in',
      'digits',
      'digit',
      'four',
      '4',
      'three',
      '3',
      'are',
      'is',
      'number',
    }.contains(_at(j))) {
      j++;
    }
    final digits = StringBuffer();
    while (j < t.length) {
      if (RegExp(r'^\d+$').hasMatch(t[j])) {
        digits.write(t[j]);
      } else if (_digitWords.containsKey(t[j])) {
        digits.write(_digitWords[t[j]]);
      } else {
        break;
      }
      j++;
    }
    if (digits.length < 3) return false;
    _ending = digits.toString();
    _mark(i, j - i);
    return true;
  }

  String? _slot() {
    if (_time != null) return null;
    if (t.contains('morning')) return 'morning';
    if (t.contains('afternoon')) return 'afternoon';
    if (t.any(const {'evening', 'tonight', 'night'}.contains)) return 'evening';
    final free =
        _seq('free', 'slot') ||
        _seq('free', 'time') ||
        _seq('next', 'available') ||
        _seq('first', 'available') ||
        _seq('any', 'time') ||
        _has(const {'earliest', 'asap', 'whenever', 'soonest'});
    return free ? 'any' : null;
  }

  String _at(int i) => i >= 0 && i < t.length ? t[i] : '';
  bool _has(Set<String> words) => t.any(words.contains);
  bool _seq(String a, String b) {
    for (var i = 0; i + 1 < t.length; i++) {
      if (t[i] == a && t[i + 1] == b) return true;
    }
    return false;
  }

  bool get _onlyConfirm =>
      t.isNotEmpty &&
      t.length <= 5 &&
      t.every(_confirmish.contains) &&
      (_has(_confirm) ||
          _seq('go', 'ahead') ||
          _seq('book', 'it') ||
          _seq('looks', 'good') ||
          _seq('thats', 'it') ||
          (t.length <= 2 && _has(const {'ok', 'okay'})));

  /// Where a closing "(and) confirm" / "save it" / "book it" starts.
  int? _trailingConfirm() {
    var e = t.length;
    while (e > 0 && const {'please', 'now', 'it'}.contains(t[e - 1])) {
      e--;
    }
    if (e == 0) return null;
    int? s;
    final last = t[e - 1];
    if (const {
      'confirm',
      'confirmed',
      'save',
      'submit',
      'done',
    }.contains(last)) {
      s = e - 1;
    } else if (last == 'ahead' && _at(e - 2) == 'go') {
      s = e - 2;
    } else if (last == 'book' && e < t.length && t[e] == 'it') {
      s = e - 1;
    }
    if (s == null) return null;
    while (s! > 0 && const {'and', 'then', 'so', 'please'}.contains(t[s - 1])) {
      s--;
    }
    return s;
  }

  VoiceCommand run() {
    final confirmAt = _trailingConfirm();
    if (confirmAt != null) _mark(confirmAt, t.length - confirmAt);
    _textFields();
    for (var i = 0; i < t.length; i++) {
      if (_used.contains(i)) continue;
      if (_endingAt(i) ||
          _paymentAt(i) ||
          _dobAt(i) ||
          _balanceAt(i) ||
          _dateAt(i) ||
          _durationAt(i) ||
          _phoneAt(i) ||
          _timeAt(i) ||
          _ageAt(i)) {
        continue;
      }
      _flagsAt(i);
    }
    _procedureReason();
    _conditionKeywords();
    final names = _names();
    _nameList = names;
    return VoiceCommand(
      intent: _intent(),
      name: names.isEmpty ? '' : names.first,
      corrected: _correctedName,
      confirmAtEnd: confirmAt != null && confirmAt > 0 && !_onlyConfirm,
      otherNames: names.length > 1 ? names.sublist(1) : const [],
      firstName: _firstName,
      lastName: _lastName,
      date: _date,
      time: _time,
      age: _age,
      dateOfBirth: _dob,
      gender: _gender,
      phone: _phone,
      email: _email,
      conditions: _conditions,
      notes: _notes.isEmpty ? null : _notes.join('. '),
      balance: _balance,
      reason: _reason,
      durationMinutes: _duration,
      homeVisit: _home,
      address: _address,
      sendWhatsApp: _whatsApp,
      addToQueue: _queue,
      slot: _slot(),
      phoneEnding: _ending,
      shiftMinutes: _shift,
      payment: _paid,
    );
  }

  VoiceIntent _intent() {
    if (t.isEmpty) return VoiceIntent.none;
    // Only short, command-only utterances count: "book Rahul and confirm"
    // is an appointment that ends in a confirm, not a bare confirm.
    if (t.length <= 5 &&
        t.every(_cancelish.contains) &&
        (_has(_cancel) ||
            _seq('never', 'mind') ||
            _seq('forget', 'it') ||
            _seq('scratch', 'that') ||
            (t.length == 1 && t.first == 'no'))) {
      return VoiceIntent.cancel;
    }
    if (_onlyConfirm) return VoiceIntent.confirm;
    if (_paid != null) return VoiceIntent.recordPayment;
    final noShow =
        _seq('no', 'show') ||
        _seq('didnt', 'show') ||
        _seq('didnt', 'come') ||
        (_seq('did', 'not') && _has(const {'come', 'show'})) ||
        _has(const {'noshow', 'absent'}) ||
        (_has(const {'missed'}) && !_has(const {'follow'}));
    if (noShow) return VoiceIntent.markMissed;
    final said =
        _nameList.isNotEmpty ||
        _has(const {'he', 'she', 'him', 'her', 'his', 'patient'});
    if (_has(const {'done', 'complete', 'completed', 'finished'}) &&
        (_has(const {'mark'}) ||
            (said && _has(const {'is', 'was', 'visit'})))) {
      return VoiceIntent.markDone;
    }
    if (_notes.isNotEmpty &&
        (_seq('a', 'note') ||
            _seq('add', 'note') ||
            _noteCues.contains(t.first) ||
            _has(const {'file', 'record', 'chart'}))) {
      return VoiceIntent.addNote;
    }
    if (_has(const {'cancel', 'drop'}) || _seq('call', 'off')) {
      return VoiceIntent.cancelAppointment;
    }
    if (_has(_editVerbs) &&
        (_has(_patientFields) || _email != null) &&
        !_has(_appointment) &&
        _date == null &&
        _time == null) {
      return VoiceIntent.editPatient;
    }
    if (_has(_reschedule) || _seq('bring', 'forward')) {
      return VoiceIntent.reschedule;
    }
    final addingPatient =
        (_has(const {'patient', 'patients'}) && _has(_addWords)) ||
        _seq('new', 'registration');
    // "Show new patients this month" is a list, not a new patient.
    final listing = _has(const {'show', 'list', 'view', 'month', 'filter'});
    if (addingPatient && !_has(_appointment) && !listing) {
      return VoiceIntent.addPatient;
    }
    if (_has(_appointment) || _seq('follow', 'up')) {
      return VoiceIntent.addAppointment;
    }
    if (_has(_open)) return VoiceIntent.openPatient;
    return VoiceIntent.none;
  }

  // ── Free-text fields: names, notes, reason, address, conditions ───────

  bool _boundary(int i) {
    final w = _at(i);
    if (w.isEmpty || _fieldCues.contains(w)) return true;
    // "…, last name Boridkar"
    if (const {'first', 'last', 'full'}.contains(w) && _at(i + 1) == 'name') {
      return true;
    }
    // "…, don't send WhatsApp", "…, add to queue"
    if (const {
      'dont',
      'send',
      'no',
      'without',
      'skip',
      'add',
      'do',
    }.contains(w)) {
      for (var k = i + 1; k <= i + 3; k++) {
        if (const {
          'whatsapp',
          'reminder',
          'sms',
          'message',
          'queue',
        }.contains(_at(k))) {
          return true;
        }
      }
    }
    if (const {'at', 'for', 'on', 'in'}.contains(w)) {
      final next = _at(i + 1);
      return _number(i + 1) != null ||
          _ordinals.containsKey(next) ||
          _weekdays.containsKey(next) ||
          next == 'the' ||
          next == 'today' ||
          next == 'tomorrow';
    }
    return false;
  }

  /// Words from [start] up to the next field, skipping a leading "is".
  List<int> _span(int start) {
    var s = start;
    while (const {
      'is',
      'are',
      'of',
      'for',
      'a',
      'an',
      'the',
      'to',
      'as',
    }.contains(_at(s))) {
      s++;
    }
    final out = <int>[];
    for (var k = s; k < t.length && !_boundary(k) && !_used.contains(k); k++) {
      out.add(k);
    }
    return out;
  }

  String _words(List<int> idx) => idx.map((i) => t[i]).join(' ');

  static String _sentence(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _title(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  void _textFields() {
    for (var i = 0; i < t.length; i++) {
      if (_used.contains(i)) continue;
      final w = t[i];

      // "first name Soham", "surname Boridkar", "her name is Priya Shah"
      if (w == 'name' || w == 'surname') {
        final kind = w == 'surname' ? 'last' : _at(i - 1);
        final isCue =
            w == 'surname' ||
            const {
              'first',
              'last',
              'full',
              'patient',
              'his',
              'her',
              'their',
              'the',
            }.contains(kind) ||
            _at(i + 1) == 'is';
        if (!isCue) continue;
        final idx = _span(i + 1)
            .where((k) => !_filler.contains(t[k]) && !_isNumberWord(t[k]))
            .take(3)
            .toList();
        if (idx.isEmpty) continue;
        final value = _title(_words(idx));
        if (kind == 'first') {
          _firstName = value;
        } else if (kind == 'last') {
          _lastName = value;
        } else {
          final parts = value.split(' ');
          _firstName = parts.first;
          _lastName = parts.length > 1 ? parts.sublist(1).join(' ') : null;
        }
        _mark(i, 1);
        _used.addAll(idx);
        if (kind == 'first' || kind == 'last') _used.add(i - 1);
        continue;
      }

      if (_noteCues.contains(w) && noteBody != null && noteFrom! > i) {
        _notes.add(_sentence(noteBody!));
        _used.add(i);
        _mark(noteFrom!, t.length - noteFrom!);
        continue;
      }
      if (_noteCues.contains(w)) {
        final idx = _span(i + 1);
        if (idx.isEmpty) continue;
        _notes.add(_sentence(_words(idx)));
        _used
          ..add(i)
          ..addAll(idx);
      } else if (_allergyCues.contains(w)) {
        final idx = _span(i + 1);
        if (idx.isEmpty) continue;
        _notes.add('Allergic to ${_words(idx)}');
        _used
          ..add(i)
          ..addAll(idx);
      } else if (_addressCues.contains(w)) {
        final idx = _span(i + 1);
        if (idx.isEmpty) continue;
        _address = _title(_words(idx));
        _used
          ..add(i)
          ..addAll(idx);
      } else if (_reasonCues.contains(w)) {
        final idx = _span(i + 1);
        if (idx.isEmpty) continue;
        _reason = _sentence(_words(idx));
        _used
          ..add(i)
          ..addAll(idx);
      } else if (_conditionCues.contains(w)) {
        var s = i + 1;
        while (const {'with', 'from', 'of'}.contains(_at(s))) {
          s++;
        }
        final idx = _span(s);
        if (idx.isEmpty) continue;
        // "diabetes and high BP" → two conditions.
        final chunk = <int>[];
        void flush() {
          if (chunk.isEmpty) return;
          final known = chunk
              .map((k) => _conditionWords[t[k]])
              .whereType<String>()
              .firstOrNull;
          _addCondition(known ?? _sentence(_words(chunk)));
          chunk.clear();
        }

        for (final k in idx) {
          if (const {'and', 'also', 'plus'}.contains(t[k])) {
            flush();
          } else {
            chunk.add(k);
          }
        }
        flush();
        _used
          ..add(i)
          ..addAll(idx);
      }
    }
  }

  void _addCondition(String c) {
    if (!_conditions.any((x) => x.toLowerCase() == c.toLowerCase())) {
      _conditions.add(c);
    }
  }

  void _conditionKeywords() {
    for (var i = 0; i < t.length; i++) {
      if (_used.contains(i)) continue;
      var c = _conditionWords[t[i]];
      if (t[i] == 'blood' && _at(i + 1) == 'pressure') {
        c = 'Hypertension';
        _used.add(i + 1);
      } else if (t[i] == 'heart' &&
          const {'disease', 'patient', 'problem'}.contains(_at(i + 1))) {
        c = 'Heart disease';
        _used.add(i + 1);
      }
      if (c == null) continue;
      _addCondition(c);
      _used.add(i);
      if (_at(i - 1) == 'high') _used.add(i - 1);
    }
  }

  /// A known procedure ("…for a root canal") when no reason was cued.
  void _procedureReason() {
    if (_reason != null) return;
    for (var k = 0; k < t.length; k++) {
      if (_used.contains(k) || !_procedures.contains(t[k])) continue;
      var s = k, e = k;
      while (_reasonModifiers.contains(_at(s - 1)) && !_used.contains(s - 1)) {
        s--;
      }
      while ((_reasonModifiers.contains(_at(e + 1)) ||
              _procedures.contains(_at(e + 1))) &&
          !_used.contains(e + 1)) {
        e++;
      }
      final idx = [for (var x = s; x <= e; x++) x];
      _reason = _sentence(_words(idx));
      _used.addAll(idx);
      return;
    }
  }

  // ── Date of birth ─────────────────────────────────────────────────────

  bool _dobAt(int i) {
    final isCue =
        _dobCues.contains(t[i]) ||
        (t[i] == 'd' && _at(i + 1) == 'o' && _at(i + 2) == 'b');
    if (!isCue) return false;
    var j = t[i] == 'd' ? i + 3 : i + 1;
    while (const {
      'on',
      'is',
      'to',
      'in',
      'date',
      'of',
      'the',
      'was',
      'year',
    }.contains(_at(j))) {
      j++;
    }
    final d = _fullDate(j) ?? _yearOnly(j);
    if (d == null) return false;
    _dob = d.$1;
    _mark(i, j + d.$2 - i);
    return true;
  }

  (DateTime, int)? _yearOnly(int j) {
    final y = _year(j);
    if (y == null) return null;
    return (DateTime(y.$1, now.month, now.day), y.$2);
  }

  /// "12th March 1990", "March 12 1990", "12 03 1990".
  (DateTime, int)? _fullDate(int j) {
    final dm = _dayOfMonth(j);
    if (dm != null) {
      var k = j + dm.$2;
      if (_at(k) == 'of') k++;
      final month =
          _months[_at(k)] ??
          (_number(k) != null && _number(k)!.$1 <= 12 ? _number(k)!.$1 : null);
      if (month != null) {
        k += _months.containsKey(_at(k)) ? 1 : _number(k)!.$2;
        if (_at(k) == 'of') k++;
        final y = _year(k) ?? _shortYear(k);
        if (y != null) return (DateTime(y.$1, month, dm.$1), k + y.$2 - j);
      }
    }
    final month = _months[_at(j)];
    if (month != null) {
      final day = _dayOfMonth(j + 1);
      if (day != null) {
        final k = j + 1 + day.$2;
        final y = _year(k);
        if (y != null) return (DateTime(y.$1, month, day.$1), k + y.$2 - j);
      }
    }
    return null;
  }

  /// "1990", "nineteen ninety four", "two thousand five", "twenty oh five".
  (int, int)? _year(int i) {
    final w = _at(i);
    final digits = int.tryParse(w);
    if (digits != null &&
        w.length == 4 &&
        digits > 1900 &&
        digits <= now.year) {
      return (digits, 1);
    }
    if (w == 'nineteen' || w == 'twenty') {
      final base = w == 'nineteen' ? 1900 : 2000;
      if (_at(i + 1) == 'oh' || _at(i + 1) == 'o') {
        final u = _units[_at(i + 2)];
        if (u != null && u < 10) return (base + u, 3);
      }
      final n = _number(i + 1);
      if (n != null && n.$1 >= 10 && n.$1 < 100) return (base + n.$1, 1 + n.$2);
    }
    if (w == 'two' && _at(i + 1) == 'thousand') {
      var k = i + 2;
      if (_at(k) == 'and') k++;
      final n = _number(k);
      if (n != null && n.$1 < 100) return (2000 + n.$1, k + n.$2 - i);
      return (2000, 2);
    }
    return null;
  }

  /// "90" in "12 03 90".
  (int, int)? _shortYear(int i) {
    final w = _at(i);
    if (w.length != 2) return null;
    final n = int.tryParse(w);
    if (n == null) return null;
    final cutoff = now.year % 100;
    return (n > cutoff ? 1900 + n : 2000 + n, 1);
  }

  // ── Package balance ───────────────────────────────────────────────────

  bool _balanceAt(int i) {
    if (!_balanceCues.contains(t[i])) return false;
    for (var j = i + 1; j <= i + 4 && j < t.length; j++) {
      final a = _amount(j);
      if (a != null) {
        _balance = a.$1;
        var end = j + a.$2;
        if (const {'rupees', 'rs', 'inr', 'only'}.contains(_at(end))) end++;
        _mark(i, end - i);
        return true;
      }
    }
    return false;
  }

  /// "5000", "five thousand", "2 lakh", "fifteen hundred", "5 k".
  (double, int)? _amount(int i) {
    var total = 0, current = 0, k = i;
    var any = false;
    while (k < t.length) {
      final w = t[k];
      final n = _number(k);
      if (n != null) {
        current += n.$1;
        k += n.$2;
      } else if (w == 'hundred') {
        current = (current == 0 ? 1 : current) * 100;
        k++;
      } else if (w == 'thousand' || w == 'k') {
        total += (current == 0 ? 1 : current) * 1000;
        current = 0;
        k++;
      } else if (w == 'lakh' || w == 'lakhs' || w == 'lac') {
        total += (current == 0 ? 1 : current) * 100000;
        current = 0;
        k++;
      } else if (w == 'and' && any) {
        k++;
        continue;
      } else {
        break;
      }
      any = true;
    }
    return any ? ((total + current).toDouble(), k - i) : null;
  }

  // ── Appointment date ──────────────────────────────────────────────────

  bool _dateAt(int i) {
    final w = t[i];
    if (w == 'today' || w == 'tonight') return _setDate(_day(0), i, 1);
    if (w == 'tomorrow') {
      final dayAfter = _at(i - 1) == 'after' && _at(i - 2) == 'day';
      return _setDate(_day(dayAfter ? 2 : 1), i, 1);
    }
    if (_weekdays.containsKey(w)) {
      final ahead = (_weekdays[w]! - now.weekday + 7) % 7;
      return _setDate(_day(ahead == 0 ? 7 : ahead), i, 1);
    }
    if (w == 'week' && _at(i - 1) == 'next') return _setDate(_day(7), i, 1);
    // "in 3 days", "in two weeks"
    if (w == 'in') {
      // "in an hour", "in half an hour"
      if (const {'an', 'a'}.contains(_at(i + 1)) &&
          const {'hour', 'hr'}.contains(_at(i + 2))) {
        return _setRelative(60, i, 3);
      }
      if (_at(i + 1) == 'half' && _at(i + 2) == 'an' && _at(i + 3) == 'hour') {
        return _setRelative(30, i, 4);
      }
      final n = _number(i + 1);
      if (n != null) {
        final unit = _at(i + 1 + n.$2);
        if (const {'minute', 'minutes', 'min', 'mins'}.contains(unit)) {
          return _setRelative(n.$1, i, n.$2 + 2);
        }
        if (const {'hour', 'hours', 'hr', 'hrs'}.contains(unit)) {
          return _setRelative(n.$1 * 60, i, n.$2 + 2);
        }
        if (unit == 'day' || unit == 'days') {
          return _setDate(_day(n.$1), i, n.$2 + 2);
        }
        if (unit == 'week' || unit == 'weeks') {
          return _setDate(_day(n.$1 * 7), i, n.$2 + 2);
        }
      }
    }
    // A full date with a past year is a birthday said without a cue.
    final full = _fullDate(i);
    if (full != null) {
      if (full.$1.year < now.year) {
        _dob = full.$1;
        _mark(i, full.$2);
        return true;
      }
      return _setDate(full.$1, i, full.$2);
    }
    // "october 5th", "oct 5"
    if (_months.containsKey(w)) {
      final n = _dayOfMonth(i + 1);
      if (n != null) return _setDate(_monthDay(_months[w], n.$1), i, 1 + n.$2);
    }
    // "5th october", "the fifth of october", "on the 5th"
    final n = _dayOfMonth(i);
    if (n != null) {
      var j = i + n.$2;
      if (_at(j) == 'of') j++;
      final month = _months[_at(j)];
      if (month != null) {
        return _setDate(_monthDay(month, n.$1), i, j + 1 - i);
      }
      if (n.$3 && (_at(i - 1) == 'the' || _at(i - 1) == 'on')) {
        return _setDate(_monthDay(null, n.$1), i, n.$2);
      }
    }
    return false;
  }

  /// "In 2 hours": today (or tomorrow) at now plus [minutes], on the
  /// 5-minute grid.
  bool _setRelative(int minutes, int i, int len) {
    var at = now.add(Duration(minutes: minutes));
    final r = at.minute % 5;
    if (r != 0) at = at.add(Duration(minutes: 5 - r));
    _date = DateTime(at.year, at.month, at.day);
    _time = TimeOfDay(hour: at.hour, minute: at.minute);
    _mark(i, len);
    return true;
  }

  bool _setDate(DateTime d, int i, int len) {
    _date = d;
    _mark(i, len);
    return true;
  }

  /// A day of the month at [i]: (day, tokens, spoken as an ordinal).
  (int, int, bool)? _dayOfMonth(int i) {
    final w = _at(i);
    if (_ordinals.containsKey(w)) return (_ordinals[w]!, 1, true);
    if (_tens.containsKey(w) && _ordinals.containsKey(_at(i + 1))) {
      final d = _tens[w]! + _ordinals[_at(i + 1)]!;
      if (d <= 31) return (d, 2, true);
    }
    final n = _number(i);
    if (n == null || n.$1 < 1 || n.$1 > 31) return null;
    final suffix = const {'th', 'st', 'nd', 'rd'}.contains(_at(i + n.$2));
    return (n.$1, n.$2 + (suffix ? 1 : 0), suffix);
  }

  /// That day this month (or [month]); rolls forward if already past.
  DateTime _monthDay(int? month, int day) {
    final today = _day(0);
    var d = DateTime(now.year, month ?? now.month, day);
    if (d.isBefore(today)) {
      d = month == null
          ? DateTime(now.year, now.month + 1, day)
          : DateTime(now.year + 1, month, day);
    }
    return d;
  }

  DateTime _day(int ahead) =>
      DateTime(now.year, now.month, now.day).add(Duration(days: ahead));

  // ── Duration ──────────────────────────────────────────────────────────

  bool _durationAt(int i) {
    if (t[i] == 'half' && _at(i + 1) == 'an' && _at(i + 2) == 'hour') {
      _duration = 30;
      _mark(i, 3);
      return true;
    }
    var n = _number(i);
    if (n == null &&
        (t[i] == 'an' || t[i] == 'a') &&
        const {'hour', 'hr'}.contains(_at(i + 1))) {
      n = (1, 1);
    }
    if (n == null) return false;
    var j = i + n.$2;
    var half = false;
    if (_at(j) == 'and' && _at(j + 1) == 'a' && _at(j + 2) == 'half') {
      half = true;
      j += 3;
    }
    final unit = _at(j);
    int minutes;
    if (const {'minute', 'minutes', 'min', 'mins'}.contains(unit)) {
      minutes = n.$1;
    } else if (const {'hour', 'hours', 'hr', 'hrs'}.contains(unit)) {
      if (_at(j + 1) == 'and' && _at(j + 2) == 'a' && _at(j + 3) == 'half') {
        half = true;
        j += 3;
      }
      minutes = n.$1 * 60 + (half ? 30 : 0);
    } else {
      return false;
    }
    // "30 minutes later", "push it by an hour": a move, not a length.
    final next = _at(j + 1);
    bool? later;
    if (const {'later', 'late', 'after', 'afterwards'}.contains(next)) {
      later = true;
      j++;
    } else if (const {'earlier', 'early', 'sooner', 'before'}.contains(next)) {
      later = false;
      j++;
    } else if (_at(i - 1) == 'by') {
      if (_has(const {'prepone', 'earlier', 'advance', 'forward', 'sooner'})) {
        later = false;
      } else if (_has(const {
        'push',
        'delay',
        'postpone',
        'later',
        'move',
        'shift',
        'extend',
      })) {
        later = true;
      }
    }
    if (later != null) {
      _shift = later ? minutes : -minutes;
    } else {
      _duration = minutes;
    }
    _mark(i, j + 1 - i);
    return true;
  }

  // ── Phone ─────────────────────────────────────────────────────────────

  bool _phoneAt(int i) {
    final cue = _phoneCues.contains(t[i]);
    var j = cue ? i + 1 : i;
    while (const {'number', 'is', 'no', 'plus', 'to'}.contains(_at(j))) {
      j++;
    }
    final digits = StringBuffer();
    while (j < t.length) {
      final w = t[j];
      if (RegExp(r'^\d+$').hasMatch(w)) {
        digits.write(w);
        j++;
      } else if (_digitWords.containsKey(w)) {
        digits.write(_digitWords[w]);
        j++;
      } else if ((w == 'double' || w == 'triple') &&
          _digitWords.containsKey(_at(j + 1))) {
        digits.write(_digitWords[_at(j + 1)]! * (w == 'double' ? 2 : 3));
        j += 2;
      } else {
        break;
      }
    }
    if (digits.length < (cue ? 7 : 10)) return false;
    final all = digits.toString();
    // Keep the last 10 digits: drops a spoken +91 or leading 0.
    _phone = all.length > 10 ? all.substring(all.length - 10) : all;
    _mark(i, j - i);
    return true;
  }

  // ── Time ──────────────────────────────────────────────────────────────

  bool _timeAt(int i) {
    final w = t[i];
    if (w == 'noon' || w == 'midday') {
      _time = const TimeOfDay(hour: 12, minute: 0);
      _used.add(i);
      return true;
    }
    if ((w == 'half' || w == 'quarter') && _at(i + 1) == 'past') {
      final n = _number(i + 2);
      if (n != null && n.$1 >= 1 && n.$1 <= 12) {
        _mark(i, 2 + n.$2);
        _time = _withMeridian(n.$1, w == 'half' ? 30 : 15, i + 2 + n.$2);
        return true;
      }
    }
    if (w == 'quarter' && _at(i + 1) == 'to') {
      final n = _number(i + 2);
      if (n != null && n.$1 >= 1 && n.$1 <= 12) {
        _mark(i, 2 + n.$2);
        _time = _withMeridian(n.$1 == 1 ? 12 : n.$1 - 1, 45, i + 2 + n.$2);
        return true;
      }
    }
    final clock = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(w);
    if (clock != null) {
      final h = int.parse(clock.group(1)!);
      final m = int.parse(clock.group(2)!);
      _used.add(i);
      _time = h > 12
          ? TimeOfDay(hour: h % 24, minute: m)
          : _withMeridian(h, m, i + 1);
      return true;
    }

    final n = _number(i);
    if (n == null || n.$1 < 1 || n.$1 > 12) return false;
    final after = i + n.$2;
    final cued = const {
      'at',
      'around',
      'by',
      'till',
      'until',
      'to',
      'it',
      'about',
    }.contains(_at(i - 1));
    final m = _number(after);
    final minute = m != null && m.$1 >= 10 && m.$1 < 60 ? m : null;
    final wordAfter =
        _meridianAt(after) != null ||
        _at(after) == 'o' ||
        _at(after) == 'clock';
    if (!cued && !wordAfter && minute == null) return false;

    var end = after;
    if (minute != null) end += minute.$2;
    _mark(i, end - i);
    _time = _withMeridian(n.$1, minute?.$1 ?? 0, end);
    return true;
  }

  /// am/pm from the words after the time, else "morning"/"evening"
  /// anywhere, else clinic hours: 8–11 is morning, 12–7 is afternoon.
  TimeOfDay _withMeridian(int hour, int minute, int i) {
    final said = _meridianAt(i) ?? _meridianAt(i + 1) ?? _meridianAt(i + 2);
    bool? dayPart;
    if (t.any(const {'evening', 'afternoon', 'night', 'tonight'}.contains)) {
      dayPart = true;
    } else if (t.contains('morning')) {
      dayPart = false;
    }
    final pm = said ?? dayPart ?? (hour == 12 || hour <= 7);
    var h = hour % 12;
    if (pm) h += 12;
    return TimeOfDay(hour: h, minute: minute);
  }

  /// true = pm, false = am, null = no meridian word at [i].
  bool? _meridianAt(int i) => switch (_at(i)) {
    'pm' || 'evening' || 'afternoon' || 'night' => true,
    'am' || 'morning' => false,
    _ => null,
  };

  // ── Age, sex, switches ────────────────────────────────────────────────

  bool _ageAt(int i) {
    final w = t[i];
    if (w == 'age' || w == 'aged') {
      var j = i + 1;
      if (const {'is', 'of', 'to'}.contains(_at(j))) j++;
      final n = _number(j);
      if (n != null) {
        _age = n.$1;
        _mark(i, j + n.$2 - i);
        return true;
      }
    }
    final n = _number(i);
    if (n == null) return false;
    final unit = _at(i + n.$2);
    if (const {'year', 'years', 'yr', 'yrs'}.contains(unit)) {
      _age = n.$1;
      _mark(i, n.$2 + 1);
      return true;
    }
    // A bare number when adding a patient is most likely their age.
    if (n.$1 > 12 && n.$1 < 110 && _age == null && t.contains('patient')) {
      _age = n.$1;
      _mark(i, n.$2);
      return true;
    }
    return false;
  }

  bool _negatedAt(int i) =>
      _negations.contains(_at(i - 1)) ||
      _negations.contains(_at(i - 2)) ||
      _negations.contains(_at(i - 3));

  void _flagsAt(int i) {
    final w = t[i];
    if (const {'male', 'man', 'boy', 'gentleman'}.contains(w)) {
      _gender = 'Male';
    } else if (const {'female', 'woman', 'girl', 'lady'}.contains(w)) {
      _gender = 'Female';
    } else if ((w == 'other' || w == 'transgender') &&
        (const {'sex', 'gender', 'is'}.contains(_at(i - 1)) ||
            w == 'transgender')) {
      _gender = 'Other';
    } else if (w == 'home' || (w == 'house' && _at(i + 1) == 'call')) {
      _home = true;
    } else if (w == 'clinic') {
      _home = false;
    } else if (w == 'whatsapp' || w == 'reminder' || w == 'sms') {
      _whatsApp = !_negatedAt(i);
    } else if (w == 'queue') {
      _queue = !_negatedAt(i);
    }
  }

  // ── Names ─────────────────────────────────────────────────────────────

  /// Whatever is left once commands, fields and filler are gone, split
  /// into patients at "and" / "with". After "no" / "sorry" / "actually",
  /// only the corrected name counts.
  bool _correctedName = false;

  List<String> _names() {
    bool isName(int i) =>
        !_used.contains(i) && !_filler.contains(t[i]) && !_isNumberWord(t[i]);
    var start = 0;
    for (var i = 0; i < t.length; i++) {
      if (_corrections.contains(t[i]) &&
          [for (var k = i + 1; k < t.length; k++) k].any(isName)) {
        start = i + 1;
      }
    }
    _correctedName = start > 0;
    final names = <String>[];
    var current = <String>[];
    for (var i = start; i < t.length; i++) {
      if (_nameJoins.contains(t[i]) && current.isNotEmpty) {
        names.add(current.join(' '));
        current = [];
      } else if (isName(i)) {
        current.add(t[i]);
      }
    }
    if (current.isNotEmpty) names.add(current.join(' '));
    return names;
  }

  // ── Numbers ───────────────────────────────────────────────────────────

  /// A number at [i] as (value, tokens used): "32", "thirty two", "five".
  (int, int)? _number(int i) {
    final w = _at(i);
    final digits = int.tryParse(w);
    if (digits != null) return (digits, 1);
    if (_units.containsKey(w)) return (_units[w]!, 1);
    if (_tens.containsKey(w)) {
      final unit = _units[_at(i + 1)];
      if (unit != null && unit > 0 && unit < 10) return (_tens[w]! + unit, 2);
      return (_tens[w]!, 1);
    }
    return null;
  }

  void _mark(int i, int len) {
    for (var k = i; k < i + len; k++) {
      _used.add(k);
    }
  }

  bool _isNumberWord(String w) =>
      int.tryParse(w) != null ||
      _units.containsKey(w) ||
      _tens.containsKey(w) ||
      _ordinals.containsKey(w);
}
