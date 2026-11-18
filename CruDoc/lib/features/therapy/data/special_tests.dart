/// Bundled orthopaedic special tests, written in plain words as a quick
/// reminder. Results only ever "may suggest" something and always need
/// clinical correlation; nothing here is a diagnosis.
enum TestRegion {
  knee('Knee'),
  shoulder('Shoulder'),
  spineHip('Spine & hip'),
  ankle('Ankle'),
  elbowWrist('Elbow & wrist');

  const TestRegion(this.label);
  final String label;
}

class SpecialTest {
  const SpecialTest({
    required this.id,
    required this.region,
    required this.name,
    required this.assesses,
    required this.steps,
    required this.positive,
    required this.suggests,
  });

  final String id;
  final TestRegion region;
  final String name;

  /// What the test looks at.
  final String assesses;
  final List<String> steps;

  /// What counts as a positive result.
  final String positive;

  /// Conservative interpretation, ending with "needs clinical correlation".
  final String suggests;
}

SpecialTest? specialTestById(String id) =>
    kSpecialTests.where((t) => t.id == id).firstOrNull;

const List<SpecialTest> kSpecialTests = [
  // Knee
  SpecialTest(
    id: 'lachman',
    region: TestRegion.knee,
    name: 'Lachman test',
    assesses:
        'Forward glide of the shin bone, mainly the front cruciate ligament.',
    steps: [
      'Patient lies on their back with the knee bent about 20 to 30 degrees.',
      'Hold the thigh steady with one hand and the upper shin with the other.',
      'Pull the shin forward and feel the amount of glide and the end feel.',
      'Compare with the other knee.',
    ],
    positive: 'More forward glide than the other side, or a soft end feel.',
    suggests:
        'May suggest laxity of the anterior cruciate ligament; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'ant_drawer_knee',
    region: TestRegion.knee,
    name: 'Anterior drawer (knee)',
    assesses: 'Forward glide of the shin bone on the thigh bone.',
    steps: [
      'Patient lies on their back with the hip bent 45 degrees and the knee bent 90 degrees, foot flat.',
      'Sit lightly on the foot to keep it still.',
      'Wrap your hands around the upper shin with thumbs on the joint line.',
      'Pull the shin forward and compare with the other knee.',
    ],
    positive: 'Clearly more forward movement than the other side.',
    suggests:
        'May suggest anterior cruciate ligament laxity; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'post_drawer_knee',
    region: TestRegion.knee,
    name: 'Posterior drawer (knee)',
    assesses:
        'Backward glide of the shin bone, mainly the back cruciate ligament.',
    steps: [
      'Patient lies on their back with the hip bent 45 degrees and the knee bent 90 degrees.',
      'First look from the side for the shin sagging backward.',
      'Hold the upper shin with both hands and push it backward.',
      'Compare the movement with the other knee.',
    ],
    positive: 'More backward movement than the other side, or visible sag.',
    suggests:
        'May suggest posterior cruciate ligament laxity; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'mcmurray',
    region: TestRegion.knee,
    name: 'McMurray test',
    assesses:
        'Painful clicking or catching linked to the knee cartilage pads (menisci).',
    steps: [
      'Patient lies on their back; bend the hip and knee fully.',
      'Hold the heel with one hand and the knee joint line with the other.',
      'Turn the foot in and out while slowly straightening the knee.',
      'Note any click, catch or pain at the joint line.',
    ],
    positive: 'Pain or a palpable click along the joint line during the turn.',
    suggests: 'May suggest a meniscal problem; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'valgus_stress_knee',
    region: TestRegion.knee,
    name: 'Valgus stress (knee)',
    assesses: 'The ligament on the inner side of the knee (medial collateral).',
    steps: [
      'Patient lies on their back with the knee straight, then repeat at about 30 degrees of bend.',
      'Support the outer knee with one hand and the ankle with the other.',
      'Push the knee inward while drawing the ankle outward.',
      'Feel for gapping and compare with the other side.',
    ],
    positive: 'Pain on the inner knee or more opening than the other side.',
    suggests:
        'May suggest medial collateral ligament involvement; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'varus_stress_knee',
    region: TestRegion.knee,
    name: 'Varus stress (knee)',
    assesses: 'The ligament on the outer side of the knee (lateral collateral).',
    steps: [
      'Patient lies on their back with the knee straight, then repeat at about 30 degrees of bend.',
      'Support the inner knee with one hand and the ankle with the other.',
      'Push the knee outward while drawing the ankle inward.',
      'Feel for gapping and compare with the other side.',
    ],
    positive: 'Pain on the outer knee or more opening than the other side.',
    suggests:
        'May suggest lateral collateral ligament involvement; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'patellar_apprehension',
    region: TestRegion.knee,
    name: 'Patellar apprehension',
    assesses: 'Willingness of the kneecap to slide sideways.',
    steps: [
      'Patient lies on their back with the knee slightly bent and the thigh muscle relaxed.',
      'Gently push the kneecap toward the outer side.',
      'Watch the face and the quadriceps for guarding.',
      'Stop at once if the patient resists or reports it feels like giving way.',
    ],
    positive:
        'The patient tenses, resists or reports the kneecap feels unstable.',
    suggests: 'May suggest kneecap instability; needs clinical correlation.',
  ),
  // Shoulder
  SpecialTest(
    id: 'neer',
    region: TestRegion.shoulder,
    name: 'Neer impingement test',
    assesses:
        'Pain when the tendons under the top of the shoulder are squeezed.',
    steps: [
      'Patient sits or stands with the arm turned inward by the side.',
      'Steady the shoulder blade with one hand.',
      'Raise the arm forward and up to full height with the other hand.',
      'Ask where, if anywhere, pain appears.',
    ],
    positive:
        'Pain at the top or front of the shoulder near the end of the lift.',
    suggests: 'May suggest subacromial pain; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'hawkins_kennedy',
    region: TestRegion.shoulder,
    name: 'Hawkins-Kennedy test',
    assesses: 'Pain when the shoulder tendons are pressed under the bony roof.',
    steps: [
      "Raise the patient's arm to 90 degrees with the elbow bent 90 degrees.",
      'Support the elbow and hold the wrist.',
      'Turn the forearm downward so the shoulder rotates inward.',
      'Ask about pain.',
    ],
    positive: 'Pain at the front or top of the shoulder during the turn.',
    suggests: 'May suggest subacromial pain; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'empty_can',
    region: TestRegion.shoulder,
    name: 'Empty can (Jobe) test',
    assesses: 'Strength and pain of the top shoulder tendon (supraspinatus).',
    steps: [
      'Patient raises both arms to 90 degrees, a little forward of the side.',
      'Turn the thumbs down as if emptying a can.',
      'Press down on the arms while the patient resists.',
      'Compare strength and pain with the other side.',
    ],
    positive: 'Pain or clear weakness compared with the other side.',
    suggests:
        'May suggest supraspinatus involvement; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'drop_arm',
    region: TestRegion.shoulder,
    name: 'Drop arm test',
    assesses: 'Ability to control the arm while lowering it from the side.',
    steps: [
      "Raise the patient's arm out to 90 degrees.",
      'Ask them to lower it slowly to the side on their own.',
      'Watch whether the movement is smooth.',
    ],
    positive: 'The arm drops suddenly or cannot be lowered with control.',
    suggests:
        'May suggest a significant rotator cuff problem; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'speeds',
    region: TestRegion.shoulder,
    name: "Speed's test",
    assesses: 'Pain at the front of the shoulder along the biceps tendon.',
    steps: [
      'Patient holds the arm forward at 90 degrees with the elbow straight and palm up.',
      'Press down on the forearm while the patient resists.',
      'Ask about pain in the groove at the front of the shoulder.',
    ],
    positive: 'Pain at the front of the shoulder along the biceps tendon.',
    suggests:
        'May suggest biceps tendon irritation; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'shoulder_apprehension',
    region: TestRegion.shoulder,
    name: 'Shoulder apprehension test',
    assesses: 'Willingness of the shoulder to move forward out of its socket.',
    steps: [
      'Patient lies on their back with the arm out at 90 degrees and the elbow bent 90 degrees.',
      'Slowly turn the arm backward (outward rotation).',
      'Stop as soon as the patient feels uneasy.',
    ],
    positive:
        'The patient looks or feels apprehensive and resists further turning.',
    suggests: 'May suggest shoulder instability; needs clinical correlation.',
  ),
  // Spine and hip
  SpecialTest(
    id: 'spurling',
    region: TestRegion.spineHip,
    name: "Spurling's test",
    assesses: 'Neck nerve root irritation causing arm symptoms.',
    steps: [
      'Patient sits; bend the neck slightly to the painful side and turn it a little.',
      'Apply gentle downward pressure on the top of the head.',
      'Stop at once if arm symptoms appear.',
    ],
    positive: 'Pain, tingling or numbness spreads into the arm on that side.',
    suggests:
        'May suggest cervical nerve root irritation; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'cervical_distraction',
    region: TestRegion.spineHip,
    name: 'Cervical distraction test',
    assesses: 'Whether lifting the head eases neck or arm symptoms.',
    steps: [
      'Patient sits or lies relaxed.',
      'Hold under the chin and the back of the head.',
      'Slowly lift the head upward to take weight off the neck.',
      'Ask whether symptoms change.',
    ],
    positive: 'Arm or neck symptoms ease during the lift.',
    suggests:
        'May suggest the symptoms come from nerve root compression in the neck; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'slr',
    region: TestRegion.spineHip,
    name: 'Straight leg raise (SLR)',
    assesses: 'Tension on the lower back nerve roots (sciatic nerve).',
    steps: [
      'Patient lies on their back with both legs straight.',
      'Lift one leg with the knee straight, holding the heel.',
      'Note the angle at which leg pain starts.',
      'Lower slightly until it eases, then gently flex the foot upward to see if pain returns.',
    ],
    positive:
        'Pain running down the leg below the knee, usually between 30 and 70 degrees.',
    suggests:
        'May suggest lumbar nerve root irritation; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'slump',
    region: TestRegion.spineHip,
    name: 'Slump test',
    assesses: 'Tension in the nerve pathway from the spine to the leg.',
    steps: [
      'Patient sits at the edge of the bed with hands behind the back.',
      'Ask them to slump the back and bend the head forward.',
      'Straighten one knee, then pull the foot upward.',
      'Release the neck bend and see if symptoms change.',
    ],
    positive:
        'The usual leg or back symptoms appear and change when the neck is released.',
    suggests:
        'May suggest increased nerve tension; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'faber',
    region: TestRegion.spineHip,
    name: 'FABER (Patrick) test',
    assesses: 'Pain from the hip joint or the joint at the back of the pelvis.',
    steps: [
      'Patient lies on their back.',
      'Place the foot of the test leg on the opposite knee.',
      'Hold the pelvis on the other side and press the bent knee gently toward the bed.',
      'Ask where the pain is felt.',
    ],
    positive:
        'Pain in the groin, hip or back of the pelvis, or the knee stays clearly higher than the other side.',
    suggests:
        'May suggest a hip or sacroiliac source; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'thomas',
    region: TestRegion.spineHip,
    name: 'Thomas test',
    assesses: 'Tightness at the front of the hip (hip flexors).',
    steps: [
      'Patient sits at the end of the bed, then lies back pulling one knee to the chest.',
      'Keep the lower back flat on the bed.',
      'Let the other leg hang relaxed.',
      'Watch whether that thigh lifts off the bed or the knee straightens.',
    ],
    positive: 'The resting thigh rises off the bed.',
    suggests: 'May suggest tight hip flexors; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'trendelenburg',
    region: TestRegion.spineHip,
    name: 'Trendelenburg test',
    assesses: 'Strength of the hip muscles that hold the pelvis level.',
    steps: [
      'Stand behind the patient.',
      'Ask them to stand on one leg for up to 30 seconds.',
      'Watch the level of the pelvis on the lifted side.',
      'Repeat on the other leg.',
    ],
    positive:
        'The pelvis drops on the lifted side, or the trunk leans over the standing leg.',
    suggests:
        'May suggest weakness of the hip abductors on the standing side; needs clinical correlation.',
  ),
  // Ankle
  SpecialTest(
    id: 'ant_drawer_ankle',
    region: TestRegion.ankle,
    name: 'Anterior drawer (ankle)',
    assesses:
        'Forward glide of the foot, mainly the front outer ankle ligament.',
    steps: [
      'Patient sits with the foot hanging relaxed at about 10 to 20 degrees of pointing down.',
      'Hold the lower shin steady with one hand.',
      'Cup the heel and pull the foot forward.',
      'Compare the glide and end feel with the other ankle.',
    ],
    positive: 'More forward glide than the other side, or a soft end feel.',
    suggests:
        'May suggest laxity of the anterior talofibular ligament; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'talar_tilt',
    region: TestRegion.ankle,
    name: 'Talar tilt',
    assesses:
        'Opening of the ankle on its outer side when the heel is tilted inward.',
    steps: [
      'Patient sits with the ankle in a neutral position.',
      'Hold the lower shin steady.',
      'Tilt the heel inward and feel how far it opens.',
      'Compare with the other ankle.',
    ],
    positive: 'More opening or pain than the other side.',
    suggests:
        'May suggest outer ankle ligament laxity; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'thompson',
    region: TestRegion.ankle,
    name: 'Thompson test',
    assesses: 'Continuity of the heel cord (Achilles tendon).',
    steps: [
      'Patient lies face down with the feet hanging over the edge of the bed.',
      'Squeeze the calf muscle firmly.',
      'Watch the foot for a small downward movement.',
      'Compare with the other side.',
    ],
    positive: 'The foot does not move when the calf is squeezed.',
    suggests:
        'May suggest a disruption of the Achilles tendon; needs clinical correlation.',
  ),
  // Elbow and wrist
  SpecialTest(
    id: 'cozens',
    region: TestRegion.elbowWrist,
    name: "Cozen's test",
    assesses:
        'Pain on the outer side of the elbow when the wrist is extended against resistance.',
    steps: [
      'Patient holds the elbow bent with the forearm turned palm down and the fist closed.',
      'Support the elbow with one hand.',
      'Ask them to bend the wrist back while you resist.',
      'Ask about pain at the outer elbow.',
    ],
    positive: 'Sharp pain at the outer elbow.',
    suggests:
        'May suggest irritation of the wrist extensor tendons at the elbow; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'mills',
    region: TestRegion.elbowWrist,
    name: "Mill's test",
    assesses: 'Pain on the outer elbow when the wrist extensors are stretched.',
    steps: [
      'Patient sits with the elbow straight.',
      'Turn the forearm palm down.',
      'Bend the wrist fully downward and the fingers in a fist.',
      'Ask about pain at the outer elbow.',
    ],
    positive: 'Pain at the outer elbow.',
    suggests:
        'May suggest irritation of the wrist extensor tendons at the elbow; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'phalen',
    region: TestRegion.elbowWrist,
    name: "Phalen's test",
    assesses: 'Symptoms of pressure on the median nerve at the wrist.',
    steps: [
      'Patient presses the backs of both hands together with the wrists bent, elbows out.',
      'Hold the position for up to one minute.',
      'Ask about tingling or numbness in the thumb, index and middle fingers.',
    ],
    positive:
        'Tingling or numbness appears in the thumb, index and middle fingers.',
    suggests:
        'May suggest median nerve compression at the wrist; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'tinel',
    region: TestRegion.elbowWrist,
    name: "Tinel's sign (wrist)",
    assesses: 'Nerve sensitivity at the front of the wrist.',
    steps: [
      'Patient rests the hand palm up.',
      'Tap lightly over the middle of the wrist crease, over the median nerve.',
      'Ask about tingling that spreads into the fingers.',
    ],
    positive:
        'Tingling or an electric feeling spreads into the thumb and nearby fingers.',
    suggests:
        'May suggest median nerve irritation at the wrist; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'finkelstein',
    region: TestRegion.elbowWrist,
    name: 'Finkelstein test',
    assesses: 'Pain along the thumb side of the wrist.',
    steps: [
      'Patient tucks the thumb inside a closed fist.',
      'Support the forearm.',
      'Gently tilt the wrist toward the little finger side.',
      'Ask about pain over the thumb side of the wrist.',
    ],
    positive: 'Sharp pain over the thumb side of the wrist.',
    suggests:
        'May suggest irritation of the thumb tendons at the wrist; needs clinical correlation.',
  ),
];
