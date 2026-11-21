// The red and yellow flags a physiotherapist screens for at intake.
//
// Red flags point at serious pathology that physiotherapy must not treat on
// its own: they are a reason to send the patient to a doctor, today. Yellow
// flags are psychosocial findings that predict a slow recovery — they change
// how care is delivered, not whether it is safe.
//
// The wording is the standard teaching for each. A clinic's own senior
// physio should read this list once and correct anything they word
// differently; nothing here is computed, so changing a label is safe.

enum FlagKind {
  red('Red flag', 'Serious pathology: refer, do not treat alone'),
  yellow('Yellow flag', 'Predicts slow recovery: changes how care is given');

  const FlagKind(this.label, this.meaning);
  final String label;
  final String meaning;
}

/// One thing to ask about.
class PhysioFlag {
  const PhysioFlag(this.id, this.kind, this.label, {this.why = ''});

  /// Stable, never reused: a saved screening stores this id.
  final String id;
  final FlagKind kind;

  /// What the physio asks, in the words they would use.
  final String label;

  /// What it would mean if present. Shown as help, not as a diagnosis.
  final String why;
}

/// What a physio asks at intake. Red first, in the order they are usually
/// screened.
const List<PhysioFlag> kPhysioFlags = [
  // ----------------------------------------------------------------- red
  PhysioFlag(
    'bladder-bowel',
    FlagKind.red,
    'Bladder or bowel changes',
    why: 'Retention or incontinence can mean cauda equina compression',
  ),
  PhysioFlag(
    'saddle-anaesthesia',
    FlagKind.red,
    'Numbness around the saddle or perineum',
    why: 'Also points at cauda equina compression',
  ),
  PhysioFlag(
    'progressive-weakness',
    FlagKind.red,
    'Weakness that is getting worse',
    why: 'Progressive neurological loss needs urgent review',
  ),
  PhysioFlag(
    'bilateral-leg',
    FlagKind.red,
    'Symptoms down both legs',
    why: 'Bilateral signs raise the suspicion of cord or cauda involvement',
  ),
  PhysioFlag(
    'cancer-history',
    FlagKind.red,
    'Past history of cancer',
    why: 'New bone pain in someone with a cancer history needs imaging',
  ),
  PhysioFlag(
    'weight-loss',
    FlagKind.red,
    'Unexplained weight loss',
  ),
  PhysioFlag(
    'night-pain',
    FlagKind.red,
    'Night pain that rest and position do not ease',
  ),
  PhysioFlag(
    'fever-infection',
    FlagKind.red,
    'Fever, chills or a recent infection',
    why: 'Raises the question of discitis or a septic joint',
  ),
  PhysioFlag(
    'trauma',
    FlagKind.red,
    'Significant injury, with a fracture possible',
  ),
  PhysioFlag(
    'steroid-use',
    FlagKind.red,
    'Long-term steroid use',
    why: 'Raises fracture risk even without much force',
  ),
  PhysioFlag(
    'unexplained-falls',
    FlagKind.red,
    'Recent falls with no explanation',
  ),
  // -------------------------------------------------------------- yellow
  PhysioFlag(
    'pain-is-harm',
    FlagKind.yellow,
    'Believes the pain means damage is being done',
  ),
  PhysioFlag(
    'fear-avoidance',
    FlagKind.yellow,
    'Has stopped moving or working for fear of harm',
  ),
  PhysioFlag(
    'low-mood',
    FlagKind.yellow,
    'Low mood, or withdrawn from usual life',
  ),
  PhysioFlag(
    'passive-expectation',
    FlagKind.yellow,
    'Expects treatment done to them to help more than their own exercise',
  ),
  PhysioFlag(
    'work-problems',
    FlagKind.yellow,
    'Unhappy at work, or work feels unsafe to return to',
  ),
  PhysioFlag(
    'support',
    FlagKind.yellow,
    'Family either over-protective or unsupportive',
  ),
  PhysioFlag(
    'claim-ongoing',
    FlagKind.yellow,
    'A compensation or legal claim is going on',
  ),
  PhysioFlag(
    'sleep',
    FlagKind.yellow,
    'Sleeping badly because of the pain',
  ),
  PhysioFlag(
    'catastrophising',
    FlagKind.yellow,
    'Expects the worst outcome',
  ),
];

/// Flags of one kind, in list order.
List<PhysioFlag> physioFlagsOf(FlagKind kind) =>
    [for (final f in kPhysioFlags) if (f.kind == kind) f];

/// The flag with [id], or null when the list no longer has it.
PhysioFlag? physioFlagById(String id) {
  for (final f in kPhysioFlags) {
    if (f.id == id) return f;
  }
  return null;
}
