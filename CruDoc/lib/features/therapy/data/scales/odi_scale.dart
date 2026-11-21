import 'package:doctor_management_app/features/therapy/data/outcome_scale.dart';

// The Oswestry Disability Index, version 2.1a — the standard measure of how
// much low back pain limits daily life.
//
// The wording below is the published instrument and must not be edited:
// a reworded option changes what the patient is answering, and the score
// stops being an ODI score. If any line here reads oddly, check it against
// the source instrument rather than improving it.
//
// Scoring is the instrument's own: the sections answered are summed and
// expressed as a percentage of the maximum those sections could score. A
// patient who skips a section (sex life is the usual one) is scored out of
// 45 rather than 50, which is why nothing here assumes ten answers.

/// Oswestry Disability Index (ODI), v2.1a.
const ScaleDef kOdiScale = ScaleDef(
  id: 'odi',
  name: 'Oswestry Disability Index',
  short: 'ODI',
  region: 'Low back',
  kind: ScaleKind.questionnaire,
  unit: '%',
  higherIsBetter: false,
  source: 'Fairbank & Pynsent, version 2.1a',
  instruction:
      'The patient answers for today only, choosing the one statement in '
      'each section that fits best. A section that does not apply is left '
      'blank and the score is taken over the rest.',
  // 10 percentage points, the figure usually cited for the ODI.
  mdc: 10,
  // A CruDoc rule, not the instrument's: eight of ten sections before a
  // percentage is shown at all. The instrument scores over whatever is
  // answered, but a figure built from three sections invites comparison
  // with one built from ten, and they are not the same measurement.
  minAnswered: 8,
  bands: [
    ScaleBand(0, 20, 'Minimal disability'),
    ScaleBand(21, 40, 'Moderate disability'),
    ScaleBand(41, 60, 'Severe disability'),
    ScaleBand(61, 80, 'Crippled by back pain'),
    ScaleBand(81, 100, 'Bed-bound, or exaggerating'),
  ],
  items: [
    ScaleItem('pain', 'Section 1 — Pain intensity', [
      'I have no pain at the moment',
      'The pain is very mild at the moment',
      'The pain is moderate at the moment',
      'The pain is fairly severe at the moment',
      'The pain is very severe at the moment',
      'The pain is the worst imaginable at the moment',
    ]),
    ScaleItem('care', 'Section 2 — Personal care (washing, dressing etc)', [
      'I can look after myself normally without causing extra pain',
      'I can look after myself normally but it causes extra pain',
      'It is painful to look after myself and I am slow and careful',
      'I need some help but manage most of my personal care',
      'I need help every day in most aspects of self-care',
      'I do not get dressed, I wash with difficulty and stay in bed',
    ]),
    ScaleItem('lifting', 'Section 3 — Lifting', [
      'I can lift heavy weights without extra pain',
      'I can lift heavy weights but it gives extra pain',
      'Pain prevents me from lifting heavy weights off the floor, but I can '
          'manage if they are conveniently placed, for example on a table',
      'Pain prevents me from lifting heavy weights, but I can manage light '
          'to medium weights if they are conveniently positioned',
      'I can lift very light weights',
      'I cannot lift or carry anything',
    ]),
    ScaleItem('walking', 'Section 4 — Walking', [
      'Pain does not prevent me walking any distance',
      'Pain prevents me from walking more than 1 mile',
      'Pain prevents me from walking more than half a mile',
      'Pain prevents me from walking more than 100 yards',
      'I can only walk using a stick or crutches',
      'I am in bed most of the time',
    ]),
    ScaleItem('sitting', 'Section 5 — Sitting', [
      'I can sit in any chair as long as I like',
      'I can only sit in my favourite chair as long as I like',
      'Pain prevents me sitting more than one hour',
      'Pain prevents me from sitting more than 30 minutes',
      'Pain prevents me from sitting more than 10 minutes',
      'Pain prevents me from sitting at all',
    ]),
    ScaleItem('standing', 'Section 6 — Standing', [
      'I can stand as long as I want without extra pain',
      'I can stand as long as I want but it gives me extra pain',
      'Pain prevents me from standing for more than 1 hour',
      'Pain prevents me from standing for more than 30 minutes',
      'Pain prevents me from standing for more than 10 minutes',
      'Pain prevents me from standing at all',
    ]),
    ScaleItem('sleeping', 'Section 7 — Sleeping', [
      'My sleep is never disturbed by pain',
      'My sleep is occasionally disturbed by pain',
      'Because of pain I have less than 6 hours sleep',
      'Because of pain I have less than 4 hours sleep',
      'Because of pain I have less than 2 hours sleep',
      'Pain prevents me from sleeping at all',
    ]),
    ScaleItem('sex', 'Section 8 — Sex life (if applicable)', [
      'My sex life is normal and causes no extra pain',
      'My sex life is normal but causes some extra pain',
      'My sex life is nearly normal but is very painful',
      'My sex life is severely restricted by pain',
      'My sex life is nearly absent because of pain',
      'Pain prevents any sex life at all',
    ]),
    ScaleItem('social', 'Section 9 — Social life', [
      'My social life is normal and gives me no extra pain',
      'My social life is normal but increases the degree of pain',
      'Pain has no significant effect on my social life apart from limiting '
          'my more energetic interests, for example sport',
      'Pain has restricted my social life and I do not go out as often',
      'Pain has restricted my social life to my home',
      'I have no social life because of pain',
    ]),
    ScaleItem('travelling', 'Section 10 — Travelling', [
      'I can travel anywhere without pain',
      'I can travel anywhere but it gives me extra pain',
      'Pain is bad but I manage journeys over two hours',
      'Pain restricts me to journeys of less than one hour',
      'Pain restricts me to short necessary journeys under 30 minutes',
      'Pain prevents me from travelling except to receive treatment',
    ]),
  ],
);
