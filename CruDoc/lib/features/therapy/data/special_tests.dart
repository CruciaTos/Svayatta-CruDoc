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
    assesses:
        'The ligament on the outer side of the knee (lateral collateral).',
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

  // -------------------------------------------------------------------
  // Second batch. Same rules as above: plain words, steps anybody trained
  // can follow, a stated positive, and an interpretation that only ever
  // "may suggest" and always ends in clinical correlation. No test here
  // diagnoses anything, and a test enforces that wording.
  // -------------------------------------------------------------------

  // Knee
  SpecialTest(
    id: 'apley',
    region: TestRegion.knee,
    name: "Apley's compression test",
    assesses: 'Pain from the meniscus under compression and rotation.',
    steps: [
      'Patient lies face down with the knee bent to 90 degrees.',
      'Steady the thigh with your own knee or hand.',
      'Press down through the heel while rotating the shin in and out.',
      'Repeat with the shin pulled upward instead of compressed.',
    ],
    positive:
        'Pain on compression with rotation that eases when the joint is '
        'pulled apart.',
    suggests:
        'May suggest a meniscal problem rather than a ligament one; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'thessaly',
    region: TestRegion.knee,
    name: 'Thessaly test',
    assesses: 'Meniscal pain under weight-bearing rotation.',
    steps: [
      'Patient stands on the affected leg, holding your hands for balance.',
      'Ask them to bend that knee to about 20 degrees.',
      'Ask them to rotate the body and knee inward and outward three times.',
      'Compare with the other leg.',
    ],
    positive: 'Joint line pain, or a sense of locking or catching.',
    suggests: 'May suggest a meniscal tear; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'patellar_grind',
    region: TestRegion.knee,
    name: "Clarke's sign (patellar grind)",
    assesses: 'Pain from the kneecap joint surface.',
    steps: [
      'Patient lies on their back with the knee straight and relaxed.',
      'Place the edge of your hand just above the kneecap.',
      'Press gently down and ask the patient to tighten the thigh.',
      'Stop as soon as pain is reported.',
    ],
    positive: 'Pain or grinding under the kneecap as the thigh tightens.',
    suggests:
        'May suggest irritation of the kneecap joint surface; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'knee_sweep',
    region: TestRegion.knee,
    name: 'Sweep test (small effusion)',
    assesses: 'A small amount of fluid in the knee.',
    steps: [
      'Patient lies on their back with the knee straight.',
      'Stroke upward along the inner side of the knee to move fluid up.',
      'Then stroke down the outer side of the thigh above the kneecap.',
      'Watch the inner side of the knee for a wave of fluid returning.',
    ],
    positive: 'A visible wave of fluid appears on the inner side.',
    suggests: 'May suggest a small joint effusion; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'noble_compression',
    region: TestRegion.knee,
    name: 'Noble compression test',
    assesses: 'Pain on the outer side of the knee from the iliotibial band.',
    steps: [
      'Patient lies on their back with the knee bent to about 90 degrees.',
      'Press your thumb on the outer side of the knee, just above the joint.',
      'Keep the pressure on and slowly straighten the knee.',
      'Ask about pain as the knee passes about 30 degrees.',
    ],
    positive: 'Pain under your thumb around 30 degrees of bend.',
    suggests:
        'May suggest iliotibial band friction at the outer knee; needs clinical correlation.',
  ),

  // Shoulder
  SpecialTest(
    id: 'obrien',
    region: TestRegion.shoulder,
    name: "O'Brien active compression test",
    assesses: 'Pain from the labrum or the joint at the top of the shoulder.',
    steps: [
      'Patient raises the arm to 90 degrees in front, elbow straight.',
      'Bring the arm about 15 degrees across the body and turn the palm down.',
      'Press down on the wrist while the patient resists.',
      'Repeat with the palm turned fully up and compare.',
    ],
    positive:
        'Pain with the palm down that eases with the palm up. Pain felt deep '
        'inside points differently from pain felt on top.',
    suggests:
        'May suggest a labral problem when felt deep in the joint, or the joint at the top of the shoulder when felt there; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'cross_body_adduction',
    region: TestRegion.shoulder,
    name: 'Cross-body adduction test',
    assesses: 'The joint at the top of the shoulder.',
    steps: [
      'Patient raises the arm to 90 degrees in front.',
      'Support the elbow and bring the arm across the chest.',
      'Take it to the end of the available range, gently.',
      'Ask where the pain is felt.',
    ],
    positive: 'Pain localised to the top of the shoulder.',
    suggests:
        'May suggest irritation of the acromioclavicular joint; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'belly_press',
    region: TestRegion.shoulder,
    name: 'Belly press test',
    assesses: 'The subscapularis muscle, at the front of the shoulder blade.',
    steps: [
      'Patient places the palm flat on their own abdomen.',
      'Ask them to press the hand into the abdomen.',
      'Watch whether the elbow drops backward as they press.',
      'Compare with the other side.',
    ],
    positive:
        'The elbow falls backward, or the wrist bends, instead of the '
        'shoulder doing the work.',
    suggests:
        'May suggest weakness of subscapularis; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'lift_off',
    region: TestRegion.shoulder,
    name: 'Lift-off test',
    assesses: 'The subscapularis muscle, with the arm behind the back.',
    steps: [
      'Patient places the back of the hand on the lower back.',
      'Ask them to lift the hand away from the back.',
      'Only use this test if that starting position is comfortable.',
      'Compare with the other side.',
    ],
    positive: 'The patient cannot lift the hand off the back.',
    suggests:
        'May suggest weakness of subscapularis; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'sulcus_sign',
    region: TestRegion.shoulder,
    name: 'Sulcus sign',
    assesses: 'Downward looseness of the shoulder joint.',
    steps: [
      'Patient sits with the arm relaxed by the side.',
      'Hold just above the elbow and pull gently straight downward.',
      'Watch for a dip appearing below the point of the shoulder.',
      'Compare with the other side.',
    ],
    positive: 'A visible dip below the tip of the shoulder.',
    suggests:
        'May suggest downward laxity of the shoulder; needs clinical correlation.',
  ),

  // Spine & hip
  SpecialTest(
    id: 'fadir',
    region: TestRegion.spineHip,
    name: 'FADIR (anterior hip impingement)',
    assesses: 'Pain at the front of the hip on bending and turning in.',
    steps: [
      'Patient lies on their back.',
      'Bend the hip and knee to 90 degrees.',
      'Turn the shin outward so the hip rotates inward, and bring the knee '
          'across the body.',
      'Ask about groin pain, and compare sides.',
    ],
    positive: 'Sharp pain in the groin at the end of the movement.',
    suggests:
        'May suggest impingement at the front of the hip; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'log_roll',
    region: TestRegion.spineHip,
    name: 'Log roll test',
    assesses: 'The hip joint itself, with the surrounding muscles relaxed.',
    steps: [
      'Patient lies on their back with the legs straight and relaxed.',
      'Hold the thigh and roll the whole leg inward, then outward.',
      'Move only the leg, keeping the pelvis still.',
      'Compare the range and the end feel with the other side.',
    ],
    positive: 'Pain, or clearly different range from the other side.',
    suggests:
        'May suggest the hip joint itself rather than the soft tissue around it; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'ober',
    region: TestRegion.spineHip,
    name: "Ober's test",
    assesses: 'Tightness of the iliotibial band on the outer thigh.',
    steps: [
      'Patient lies on the unaffected side with the lower knee bent.',
      'Bring the upper leg back in line with the body, knee bent to 90 '
          'degrees.',
      'Steady the pelvis and let the upper leg lower toward the table.',
      'Note how far it drops, and compare with the other side.',
    ],
    positive: 'The leg stays up and does not lower toward the table.',
    suggests:
        'May suggest tightness of the iliotibial band; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'prone_instability',
    region: TestRegion.spineHip,
    name: 'Prone instability test',
    assesses: 'Whether low back pain eases when the trunk muscles are working.',
    steps: [
      'Patient lies face down over the table with the legs hanging off and '
          'feet on the floor.',
      'Press gently downward over each low back segment and note any pain.',
      'Ask the patient to lift their legs off the floor and hold.',
      'Press over the same segments again and compare.',
    ],
    positive:
        'Pain present when the legs are down but reduced when they are '
        'lifted.',
    suggests:
        'May suggest the back responds to trunk strengthening; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'sij_compression',
    region: TestRegion.spineHip,
    name: 'Sacroiliac compression test',
    assesses: 'Pain reproduced from the sacroiliac joint.',
    steps: [
      'Patient lies on their side with the painful side uppermost.',
      'Place both hands over the upper rim of the pelvis.',
      'Press straight downward through the pelvis and hold briefly.',
      'Ask whether their usual pain is reproduced.',
    ],
    positive: 'The patient\'s familiar buttock or pelvic pain is reproduced.',
    suggests:
        'May suggest the sacroiliac joint as a pain source, and is read alongside the other provocation tests rather than alone; needs clinical correlation.',
  ),

  // Ankle
  SpecialTest(
    id: 'fibular_squeeze',
    region: TestRegion.ankle,
    name: 'Fibular squeeze test',
    assesses: 'The ligament joining the two shin bones above the ankle.',
    steps: [
      'Patient lies down or sits with the leg supported.',
      'Squeeze the two shin bones together at mid-calf level.',
      'Ask where pain is felt.',
      'Stop if pain is sharp.',
    ],
    positive:
        'Pain felt lower down, at the ankle rather than under your '
        'hands.',
    suggests:
        'May suggest injury to the ligament between the shin bones; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'kleiger',
    region: TestRegion.ankle,
    name: 'Kleiger external rotation test',
    assesses:
        'The ligament between the shin bones, and the inner ankle ligament.',
    steps: [
      'Patient sits with the knee bent to 90 degrees and the leg hanging.',
      'Steady the lower leg with one hand.',
      'Hold the foot and rotate it gently outward.',
      'Ask where the pain is felt.',
    ],
    positive: 'Pain above the ankle, or on the inner side of the ankle.',
    suggests:
        'May suggest injury between the shin bones or to the inner ankle ligament; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'windlass',
    region: TestRegion.ankle,
    name: 'Windlass test',
    assesses: 'Pain from the plantar fascia under the sole.',
    steps: [
      'Patient stands with the foot flat on a step, weight on that leg.',
      'Pull the big toe upward as far as it will go.',
      'Ask about pain under the heel or along the arch.',
      'Compare with the other foot.',
    ],
    positive: 'Pain under the heel or along the arch as the toe is lifted.',
    suggests:
        'May suggest plantar fascia irritation; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'tarsal_tunnel_tinel',
    region: TestRegion.ankle,
    name: 'Tarsal tunnel tap',
    assesses: 'Nerve irritation behind the inner ankle bone.',
    steps: [
      'Patient lies down with the foot relaxed.',
      'Find the soft area just behind and below the inner ankle bone.',
      'Tap gently over it several times.',
      'Ask whether anything shoots into the sole or toes.',
    ],
    positive: 'Tingling or shooting into the sole or the toes.',
    suggests:
        'May suggest irritation of the nerve behind the inner ankle; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'single_heel_raise',
    region: TestRegion.ankle,
    name: 'Single-leg heel raise',
    assesses: 'Calf strength and the inner arch support on one leg.',
    steps: [
      'Patient stands on one leg, holding a counter for balance only.',
      'Ask them to rise onto the ball of the foot and lower slowly.',
      'Count how many they manage with good height.',
      'Watch whether the heel turns inward at the top, and compare sides.',
    ],
    positive:
        'Noticeably fewer repetitions than the other side, a lower lift, or '
        'a heel that does not turn inward.',
    suggests:
        'May suggest calf or inner arch tendon weakness; needs clinical correlation.',
  ),

  // Elbow & wrist
  SpecialTest(
    id: 'medial_epicondyle',
    region: TestRegion.elbowWrist,
    name: 'Medial epicondyle test',
    assesses: 'Pain at the inner elbow from the wrist flexor tendons.',
    steps: [
      'Patient sits with the elbow bent and the forearm supported, palm up.',
      'Steady the elbow with one hand.',
      'Straighten the elbow and wrist while the patient resists gently.',
      'Ask about pain at the bony point on the inner elbow.',
    ],
    positive: 'Pain over the inner elbow bony point.',
    suggests:
        'May suggest irritation of the wrist flexor tendons at the elbow; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'elbow_valgus_stress',
    region: TestRegion.elbowWrist,
    name: 'Elbow valgus stress test',
    assesses: 'The ligament on the inner side of the elbow.',
    steps: [
      'Patient sits with the elbow bent about 20 to 30 degrees.',
      'Hold the upper arm steady and take the wrist with your other hand.',
      'Push the forearm gently outward, opening the inner side of the elbow.',
      'Feel the end point and compare with the other elbow.',
    ],
    positive: 'More opening than the other side, or pain on the inner side.',
    suggests:
        'May suggest laxity of the inner elbow ligament; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'watson_shift',
    region: TestRegion.elbowWrist,
    name: "Watson's scaphoid shift test",
    assesses: 'Movement of the scaphoid bone on the thumb side of the wrist.',
    steps: [
      'Hold the patient\'s wrist with your thumb over the scaphoid, at the '
          'base of the thumb.',
      'Tilt the wrist toward the little finger side.',
      'Keep pressing on the scaphoid and tilt the wrist back toward the '
          'thumb side.',
      'Feel for a clunk and ask about pain.',
    ],
    positive: 'A clunk as pressure is released, with pain.',
    suggests:
        'May suggest instability between the wrist bones; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'cmc_grind',
    region: TestRegion.elbowWrist,
    name: 'Thumb grind test',
    assesses: 'The joint at the base of the thumb.',
    steps: [
      'Hold the patient\'s hand steady with one hand.',
      'Grip the thumb and press it gently into the joint at its base.',
      'Rotate the thumb while keeping the pressure on.',
      'Ask about pain and listen for grinding.',
    ],
    positive: 'Pain or grinding at the base of the thumb.',
    suggests:
        'May suggest wear in the joint at the base of the thumb; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'carpal_compression',
    region: TestRegion.elbowWrist,
    name: 'Carpal compression test',
    assesses: 'Nerve compression at the front of the wrist.',
    steps: [
      'Patient rests the forearm with the palm facing up.',
      'Place both thumbs over the middle of the wrist crease.',
      'Press evenly and hold for up to 30 seconds.',
      'Ask about tingling or numbness in the thumb, index or middle finger.',
    ],
    positive:
        'Tingling or numbness in the thumb, index or middle finger within '
        '30 seconds.',
    suggests:
        'May suggest median nerve compression at the wrist; needs clinical correlation.',
  ),

  // Third batch, to round out the thinner regions.
  SpecialTest(
    id: 'patellar_tap',
    region: TestRegion.knee,
    name: 'Patellar tap (ballottement)',
    assesses: 'A larger amount of fluid in the knee.',
    steps: [
      'Patient lies on their back with the knee straight and relaxed.',
      'Use one hand to push fluid down from above the kneecap.',
      'Tap the kneecap downward with a finger of the other hand.',
      'Feel whether it floats and bounces back.',
    ],
    positive:
        'The kneecap feels as though it floats, and springs back when '
        'tapped.',
    suggests:
        'May suggest a moderate or large joint effusion; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'er_lag_sign',
    region: TestRegion.shoulder,
    name: 'External rotation lag sign',
    assesses: 'Whether the outward-turning cuff muscles can hold a position.',
    steps: [
      'Patient sits with the elbow bent to 90 degrees and held out from the '
          'side.',
      'Passively turn the forearm outward to near its end range.',
      'Ask the patient to hold that position and let go.',
      'Watch whether the forearm drifts back inward, and by how much.',
    ],
    positive: 'The arm drifts inward rather than holding where it was put.',
    suggests:
        'May suggest a tear of the outward-turning cuff tendons; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'gaenslen',
    region: TestRegion.spineHip,
    name: "Gaenslen's test",
    assesses: 'Pain reproduced from the sacroiliac joint.',
    steps: [
      'Patient lies on their back near the edge of the table.',
      'Ask them to hold one knee to the chest.',
      'Let the other leg hang off the edge and press it gently downward.',
      'Ask whether their usual pain is reproduced, then repeat on the other '
          'side.',
    ],
    positive: 'The familiar buttock or pelvic pain is reproduced.',
    suggests:
        'May suggest the sacroiliac joint as a pain source, and is read with the other provocation tests rather than alone; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'crossed_slr',
    region: TestRegion.spineHip,
    name: 'Crossed straight leg raise',
    assesses: 'Nerve root irritation, tested from the unaffected side.',
    steps: [
      'Patient lies flat on their back.',
      'Lift the pain-free leg straight, keeping the knee extended.',
      'Ask whether pain appears in the other, affected leg.',
      'Note the angle at which it appears.',
    ],
    positive: 'Raising the good leg reproduces pain down the affected leg.',
    suggests:
        'May suggest nerve root irritation on the painful side; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'hip_scour',
    region: TestRegion.spineHip,
    name: 'Hip scour (quadrant) test',
    assesses: 'The joint surface of the hip through its range.',
    steps: [
      'Patient lies on their back with the hip and knee bent to 90 degrees.',
      'Hold the knee and apply gentle pressure down through the thigh.',
      'Move the hip in an arc from inward-and-across to outward-and-open.',
      'Note any catching, grinding or pain, and compare sides.',
    ],
    positive: 'Pain, catching or grinding at some point in the arc.',
    suggests:
        'May suggest a problem with the hip joint surface; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'calcaneal_squeeze',
    region: TestRegion.ankle,
    name: 'Calcaneal squeeze test',
    assesses: 'Bone tenderness in the heel.',
    steps: [
      'Patient lies face down with the knee bent, or sits with the leg '
          'supported.',
      'Cup the heel bone between the heels of both your hands.',
      'Squeeze the sides of the heel bone together firmly.',
      'Ask about deep, localised pain in the bone.',
    ],
    positive: 'Sharp, deep pain on squeezing the sides of the heel bone.',
    suggests:
        'May suggest bone rather than soft tissue as the source, including a stress injury, and warrants imaging if suspicion is high; needs clinical correlation.',
  ),
  SpecialTest(
    id: 'elbow_extension_test',
    region: TestRegion.elbowWrist,
    name: 'Elbow extension test',
    assesses: 'Whether a recently injured elbow can fully straighten.',
    steps: [
      'Ask the patient to sit with both arms held out in front.',
      'Ask them to straighten both elbows fully, as far as they will go.',
      'Compare the two sides.',
      'Then ask them to bend both elbows fully.',
    ],
    positive: 'The injured elbow cannot straighten as far as the other.',
    suggests:
        'May suggest a bony injury after elbow trauma and is used to decide whether imaging is needed; a full range makes a fracture less likely but does not exclude one; needs clinical correlation.',
  ),
];
