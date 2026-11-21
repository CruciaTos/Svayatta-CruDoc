import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';

/// The phrases a physiotherapist taps instead of typing the same sentence
/// twenty times a day.
///
/// A session note is mostly the same handful of statements: how the patient
/// arrived, what was done, how they tolerated it, what comes next. Typing
/// those out is why session notes get skipped, and a skipped note is a
/// treatment nobody can account for later.
///
/// Two rules hold the list together, and both exist so that tapping a chip
/// can never put a finding in the record that the physio did not make:
///
///  * A phrase states only what the physio has chosen by tapping it. None of
///    them assert a measurement.
///  * A phrase that needs a number or a name carries [blank] where it goes.
///    The editor drops the cursor on that gap, so the note reads as
///    unfinished until the physio fills it, rather than carrying a plausible
///    default nobody checked.
///
/// The wording is drawn from ordinary musculoskeletal physiotherapy charting
/// and still needs a physiotherapist's read-through before it is relied on in
/// a clinic — in particular the Plan phrases, which shade into advice.

/// The gap in a phrase where the physio types a value.
///
/// A single character so it is unmistakable on screen and cheap to find
/// again when placing the cursor.
const String blank = '…';

/// One tappable phrase.
class SoapPhrase {
  const SoapPhrase(this.section, this.text);

  final SoapSection section;

  /// The sentence inserted into the note, [blank] included.
  final String text;

  /// Where the caret should sit after inserting, measured from the start of
  /// the inserted text. The gap itself when there is one, so the physio can
  /// type straight over it, otherwise the end of the phrase.
  int get caretOffset {
    final at = text.indexOf(blank);
    return at < 0 ? text.length : at;
  }

  /// Whether inserting this phrase leaves something to fill in.
  bool get hasBlank => text.contains(blank);

  /// What the chip shows. The gap is not worth a line of its own on a chip,
  /// so it stays in place and the chip reads as the sentence it inserts.
  String get label => text;
}

/// The phrases, grouped by the SOAP section they belong to.
///
/// Ordered within each section the way a session actually runs, so the chip a
/// physio wants next is usually the next one along.
const List<SoapPhrase> kSoapPhrases = [
  // Subjective — what the patient reports on arrival.
  SoapPhrase(SoapSection.subjective, 'Reports pain $blank/10 today.'),
  SoapPhrase(SoapSection.subjective, 'Reports improvement since last visit.'),
  SoapPhrase(SoapSection.subjective, 'Reports no change since last visit.'),
  SoapPhrase(
    SoapSection.subjective,
    'Reports symptoms worse since last '
    'visit.',
  ),
  SoapPhrase(SoapSection.subjective, 'Pain disturbing sleep.'),
  SoapPhrase(
    SoapSection.subjective,
    'Sleeping through the night without '
    'pain.',
  ),
  SoapPhrase(SoapSection.subjective, 'Pain on $blank, eased by rest.'),
  SoapPhrase(
    SoapSection.subjective,
    'Morning stiffness lasting $blank '
    'minutes.',
  ),
  SoapPhrase(
    SoapSection.subjective,
    'Completing the home programme as '
    'prescribed.',
  ),
  SoapPhrase(
    SoapSection.subjective,
    'Home programme done $blank days this '
    'week.',
  ),
  SoapPhrase(
    SoapSection.subjective,
    'Has not been able to do the home '
    'programme.',
  ),
  SoapPhrase(SoapSection.subjective, 'Back at work on light duties.'),
  SoapPhrase(SoapSection.subjective, 'No new complaints.'),

  // Objective — what the physio did and observed.
  SoapPhrase(
    SoapSection.objective,
    'Range of motion unchanged from last '
    'assessment.',
  ),
  SoapPhrase(SoapSection.objective, 'Range of motion improved at $blank.'),
  SoapPhrase(SoapSection.objective, 'Tenderness on palpation over $blank.'),
  SoapPhrase(SoapSection.objective, 'No tenderness on palpation today.'),
  SoapPhrase(SoapSection.objective, 'Swelling reduced.'),
  SoapPhrase(SoapSection.objective, 'Antalgic gait.'),
  SoapPhrase(SoapSection.objective, 'Gait pattern normal, no aid.'),
  SoapPhrase(SoapSection.objective, 'Walking with $blank for support.'),
  SoapPhrase(SoapSection.objective, 'Mobilisation to $blank, grade $blank.'),
  SoapPhrase(SoapSection.objective, 'Soft tissue release to $blank.'),
  SoapPhrase(
    SoapSection.objective,
    'Strengthening as per programme, '
    '$blank sets.',
  ),
  SoapPhrase(SoapSection.objective, 'Exercises progressed this session.'),
  SoapPhrase(
    SoapSection.objective,
    'Exercise technique corrected and '
    'rechecked.',
  ),
  SoapPhrase(
    SoapSection.objective,
    'Tolerated the session well, no adverse '
    'reaction.',
  ),
  SoapPhrase(SoapSection.objective, 'Session cut short — $blank.'),

  // Assessment — the physio's reading of it.
  SoapPhrase(SoapSection.assessment, 'Progressing as expected.'),
  SoapPhrase(SoapSection.assessment, 'Progressing slower than expected.'),
  SoapPhrase(SoapSection.assessment, 'Goals on track for the target date.'),
  SoapPhrase(
    SoapSection.assessment,
    'Plateau — treatment plan to be '
    'reviewed.',
  ),
  SoapPhrase(SoapSection.assessment, 'Flare-up, likely from $blank.'),
  SoapPhrase(
    SoapSection.assessment,
    'Functionally independent for daily '
    'activities.',
  ),
  SoapPhrase(SoapSection.assessment, 'Ready for discharge planning.'),

  // Plan — what happens next.
  SoapPhrase(SoapSection.plan, 'Continue the current plan.'),
  SoapPhrase(SoapSection.plan, 'Progress the home programme next session.'),
  SoapPhrase(SoapSection.plan, 'Home programme reissued and explained.'),
  SoapPhrase(SoapSection.plan, 'Review in $blank days.'),
  SoapPhrase(SoapSection.plan, 'Next session $blank.'),
  SoapPhrase(SoapSection.plan, 'Advised to rest the area for $blank days.'),
  SoapPhrase(SoapSection.plan, 'Advised ice after activity.'),
  SoapPhrase(SoapSection.plan, 'Reassess range of motion next session.'),
  SoapPhrase(SoapSection.plan, 'Refer back to the referring doctor.'),
  SoapPhrase(SoapSection.plan, 'Discharge after $blank more sessions.'),
];

/// The phrases of one section, in order.
List<SoapPhrase> soapPhrasesOf(SoapSection section) => [
  for (final p in kSoapPhrases)
    if (p.section == section) p,
];

/// The note with [phrase] inserted at [caret], and where the caret lands
/// afterwards.
///
/// Phrases go in as their own line, because a session note is read as a list
/// of statements and running two of them together makes both harder to find.
/// Inserting mid-note is honoured rather than redirected to the end: the
/// physio put the cursor where the sentence belongs.
({String text, int caret}) insertSoapPhrase(
  String note,
  int caret,
  SoapPhrase phrase,
) {
  // A caret of -1 means the field was never focused, so the phrase goes at
  // the end, which is where someone who has not clicked into the note is
  // looking.
  final at = caret < 0 || caret > note.length ? note.length : caret;
  final before = note.substring(0, at);
  final after = note.substring(at);

  // Only add the separating newline when there is something to separate
  // from, so the first phrase does not open the note with a blank line.
  final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
  final trail = after.isEmpty || after.startsWith('\n') ? '' : '\n';

  return (
    text: '$before$lead${phrase.text}$trail$after',
    caret: before.length + lead.length + phrase.caretOffset,
  );
}
