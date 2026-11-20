import 'package:flutter/material.dart';

/// Body regions the exercise library is grouped by.
enum ExerciseRegion {
  neck('Neck', Icons.face_rounded),
  shoulder('Shoulder', Icons.accessibility_new_rounded),
  elbowWrist('Elbow / wrist', Icons.back_hand_outlined),
  upperBack('Upper back', Icons.airline_seat_recline_normal_rounded),
  lowBack('Low back', Icons.airline_seat_flat_rounded),
  hip('Hip', Icons.directions_walk_rounded),
  knee('Knee', Icons.directions_run_rounded),
  ankleFoot('Ankle / foot', Icons.do_not_step_rounded),
  core('Core', Icons.self_improvement_rounded),
  balance('Balance', Icons.balance_rounded),
  breathing('Breathing', Icons.air_rounded);

  const ExerciseRegion(this.label, this.icon);
  final String label;
  final IconData icon;

  static ExerciseRegion fromName(String? n) => ExerciseRegion.values.firstWhere(
    (r) => r.name == n,
    orElse: () => ExerciseRegion.core,
  );
}

enum ExerciseLevel {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const ExerciseLevel(this.label);
  final String label;

  static ExerciseLevel fromName(String? n) => ExerciseLevel.values.firstWhere(
    (l) => l.name == n,
    orElse: () => ExerciseLevel.easy,
  );
}

/// One exercise: bundled in the library, or added by the physio.
class ExerciseDef {
  const ExerciseDef({
    required this.id,
    required this.name,
    required this.region,
    required this.goal,
    required this.steps,
    required this.cautions,
    this.sets = 3,
    this.reps = 10,
    this.holdSeconds = 0,
    this.perDay = 1,
    this.level = ExerciseLevel.easy,
    this.isCustom = false,
    this.recordId,
    this.photoPath,
    this.videoPath,
    this.videoLink,
    this.muscles = const [],
  });

  final String id;
  final String name;
  final ExerciseRegion region;
  final String goal;

  /// The muscles this exercise mainly works, as side-neutral ids from the
  /// 3D viewer's catalogue (`assets/muscle_viewer/catalog.json`) with the
  /// `_l`/`_r` suffix left off: the chart highlights both sides.
  ///
  /// Primary targets only, not every synergist, so a highlighted chart stays
  /// readable. Empty for an exercise whose point is movement rather than a
  /// muscle (ankle alphabet, balance work, breathing drills) and for a
  /// physio's own custom exercise, which has nowhere to record this yet.
  ///
  /// Every id is checked against the catalogue by
  /// `test/features/exercise_muscles_test.dart`, since a wrong id would
  /// silently highlight nothing.
  final List<String> muscles;
  final List<String> steps;

  /// Common mistakes and when to stop.
  final String cautions;
  final int sets;
  final int reps;
  final int holdSeconds;
  final int perDay;
  final ExerciseLevel level;
  final bool isCustom;

  /// The record that stores this exercise (custom) or its attached media.
  final String? recordId;
  final String? photoPath;
  final String? videoPath;
  final String? videoLink;

  bool get hasMedia =>
      photoPath != null || videoPath != null || videoLink != null;

  bool get hasMuscles => muscles.isNotEmpty;

  ExerciseDef withMedia({
    String? recordId,
    String? photoPath,
    String? videoPath,
    String? videoLink,
  }) => ExerciseDef(
    id: id,
    name: name,
    region: region,
    goal: goal,
    steps: steps,
    cautions: cautions,
    sets: sets,
    reps: reps,
    holdSeconds: holdSeconds,
    perDay: perDay,
    level: level,
    isCustom: isCustom,
    muscles: muscles,
    recordId: recordId ?? this.recordId,
    photoPath: photoPath,
    videoPath: videoPath,
    videoLink: videoLink,
  );
}

const _stop =
    'Stop if you feel sharp pain, dizziness, numbness or tingling, and tell your physiotherapist.';

/// Bundled, well-known rehab exercises. Wording is general guidance for the
/// physiotherapist to adapt, not a diagnosis.
const List<ExerciseDef> kExerciseLibrary = [
  // Neck
  ExerciseDef(
    id: 'neck-chin-tuck',
    muscles: [
      'm_longus_colli_muscle',
      'm_longus_capitis_muscle',
    ],
    name: 'Chin tuck',
    region: ExerciseRegion.neck,
    goal: 'Wakes up the deep neck muscles and improves head posture.',
    steps: [
      'Sit or stand tall, looking straight ahead.',
      'Gently draw your chin straight back, as if making a double chin.',
      'Keep your eyes level; do not tilt your head down.',
      'Hold, then relax slowly.',
    ],
    cautions: 'Do not push hard or jut the chin up. $_stop',
    sets: 2,
    reps: 10,
    holdSeconds: 5,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'neck-side-stretch',
    muscles: [
      'm_sternocleidomastoid_muscle',
      'm_scalenus_anterior_muscle',
      'm_scalenus_medius_muscle',
      'm_descending_part_of_trapezius_muscle',
    ],
    name: 'Neck side stretch',
    region: ExerciseRegion.neck,
    goal: 'Eases tightness on the side of the neck and upper shoulder.',
    steps: [
      'Sit tall with your shoulders relaxed.',
      'Slowly tilt your ear toward your shoulder.',
      'Rest one hand lightly on your head for a gentle extra stretch.',
      'Hold, then return to the middle and repeat on the other side.',
    ],
    cautions: 'Do not shrug or pull on the head. $_stop',
    sets: 2,
    reps: 3,
    holdSeconds: 20,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'neck-rotation',
    muscles: [
      'm_sternocleidomastoid_muscle',
      'm_splenius_capitis_muscle',
      'm_splenius_colli_muscle',
    ],
    name: 'Neck rotation',
    region: ExerciseRegion.neck,
    goal: 'Keeps the neck turning smoothly.',
    steps: [
      'Sit tall, shoulders relaxed.',
      'Slowly turn your head to look over one shoulder.',
      'Pause, then turn back to the middle.',
      'Repeat to the other side.',
    ],
    cautions: 'Move slowly, no jerks. $_stop',
    sets: 2,
    reps: 10,
    perDay: 2,
  ),
  // Shoulder
  ExerciseDef(
    id: 'shoulder-pendulum',
    name: 'Pendulum swing',
    region: ExerciseRegion.shoulder,
    goal: 'Gentle early movement for a stiff or painful shoulder.',
    steps: [
      'Lean forward, supporting yourself with one hand on a table.',
      'Let the other arm hang down, relaxed.',
      'Gently swing it forward and back, then side to side, then in small circles.',
      'Let the body sway move the arm; do not use the arm muscles.',
    ],
    cautions: 'Keep the movement small and relaxed. $_stop',
    sets: 2,
    reps: 10,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'shoulder-wall-slide',
    muscles: [
      'm_serratus_anterior_muscle',
      'm_ascending_part_of_trapezius_muscle',
      'm_transverse_part_of_trapezius_muscle',
    ],
    name: 'Wall slide',
    region: ExerciseRegion.shoulder,
    goal: 'Improves overhead reach and shoulder blade control.',
    steps: [
      'Stand facing a wall with forearms resting on it.',
      'Slowly slide your arms up the wall as far as comfortable.',
      'Keep your shoulders down away from your ears.',
      'Slide back down with control.',
    ],
    cautions: 'Do not arch your lower back. $_stop',
    sets: 2,
    reps: 10,
    perDay: 2,
    level: ExerciseLevel.medium,
  ),
  ExerciseDef(
    id: 'shoulder-ext-rotation',
    muscles: [
      'm_infraspinatus_muscle',
      'm_teres_minor_muscle',
    ],
    name: 'Band external rotation',
    region: ExerciseRegion.shoulder,
    goal: 'Strengthens the rotator cuff at the back of the shoulder.',
    steps: [
      'Tie a resistance band at elbow height and hold the end.',
      'Keep your elbow bent at 90 degrees, tucked against your side.',
      'Rotate your forearm outward, away from your belly.',
      'Return slowly to the start.',
    ],
    cautions: 'Keep the elbow tucked in. $_stop',
    sets: 3,
    reps: 12,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  ExerciseDef(
    id: 'shoulder-scap-squeeze',
    muscles: [
      'm_rhomboid_major_muscle',
      'm_rhomboid_minor_muscle',
      'm_transverse_part_of_trapezius_muscle',
    ],
    name: 'Shoulder blade squeeze',
    region: ExerciseRegion.shoulder,
    goal: 'Strengthens the muscles between the shoulder blades.',
    steps: [
      'Sit or stand tall with arms relaxed.',
      'Squeeze your shoulder blades together and slightly down.',
      'Hold, keeping your neck relaxed.',
      'Release slowly.',
    ],
    cautions: 'Do not shrug. $_stop',
    sets: 2,
    reps: 10,
    holdSeconds: 5,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'shoulder-cross-body-stretch',
    muscles: [
      'm_scapular_spinal_part_of_deltoid_muscle',
      'm_infraspinatus_muscle',
      'm_teres_minor_muscle',
    ],
    name: 'Cross-body shoulder stretch',
    region: ExerciseRegion.shoulder,
    goal: 'Stretches the back of the shoulder.',
    steps: [
      'Bring one arm across your chest at shoulder height.',
      'Use your other hand to hold it gently just above the elbow.',
      'Hold the stretch, then switch sides.',
    ],
    cautions: 'Keep the shoulders relaxed and do not pull hard. $_stop',
    sets: 3,
    reps: 3,
    holdSeconds: 30,
    perDay: 2,
  ),
  // Elbow / wrist
  ExerciseDef(
    id: 'wrist-flexor-stretch',
    muscles: [
      'm_flexor_carpi_radialis',
      'm_humeral_head_of_flexor_carpi_ulnaris',
      'm_ulnar_head_of_flexor_carpi_ulnaris',
    ],
    name: 'Wrist flexor stretch',
    region: ExerciseRegion.elbowWrist,
    goal: 'Stretches the forearm muscles on the palm side.',
    steps: [
      'Straighten your arm in front of you, palm up.',
      'With the other hand, gently pull your fingers back toward you.',
      'Feel the stretch along the inner forearm.',
      'Hold, then release.',
    ],
    cautions: 'Stretch gently, never to pain. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 30,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'wrist-extensor-stretch',
    muscles: [
      'm_extensor_carpi_radialis_longus',
      'm_extensor_carpi_radialis_brevis',
      'm_humeral_head_of_extensor_carpi_ulnaris',
      'm_ulnar_head_of_extensor_carpi_ulnaris',
    ],
    name: 'Wrist extensor stretch',
    region: ExerciseRegion.elbowWrist,
    goal: 'Stretches the forearm muscles on the back of the arm.',
    steps: [
      'Straighten your arm in front of you, palm down.',
      'With the other hand, gently bend the wrist down.',
      'Feel the stretch along the outer forearm.',
      'Hold, then release.',
    ],
    cautions: 'Keep the elbow straight and the stretch gentle. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 30,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'elbow-eccentric-curl',
    muscles: [
      'm_flexor_carpi_radialis',
      'm_extensor_carpi_radialis_longus',
      'm_extensor_carpi_radialis_brevis',
    ],
    name: 'Slow wrist curl with weight',
    region: ExerciseRegion.elbowWrist,
    goal: 'Builds forearm strength with slow, controlled lowering.',
    steps: [
      'Rest your forearm on a table, wrist past the edge, palm down.',
      'Hold a light weight and lift the wrist up with the other hand.',
      'Slowly lower it down over about 3 seconds using the working arm.',
      'Repeat.',
    ],
    cautions: 'Start light. $_stop',
    sets: 3,
    reps: 12,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  // Upper / mid back
  ExerciseDef(
    id: 'back-thoracic-extension',
    muscles: [
      'm_spinalis_thoracis_muscle',
      'm_longissimus_thoracis_muscle',
      'm_semispinalis_thoracis_muscle',
    ],
    name: 'Chair thoracic extension',
    region: ExerciseRegion.upperBack,
    goal: 'Opens up a stiff, rounded upper back.',
    steps: [
      'Sit on a chair with a firm backrest, hands behind your head.',
      'Gently lean back over the top of the backrest.',
      'Look slightly up and breathe out.',
      'Return to upright.',
    ],
    cautions: 'Support your head; do not strain the neck. $_stop',
    sets: 2,
    reps: 10,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'back-open-book',
    muscles: [
      'm_multifidus_thoracis_muscle',
      'm_rotatores',
      'm_external_abdominal_oblique_muscle',
    ],
    name: 'Open book rotation',
    region: ExerciseRegion.upperBack,
    goal: 'Improves upper back rotation.',
    steps: [
      'Lie on your side with knees bent and arms stretched in front.',
      'Lift the top arm and open it across your body like a book.',
      'Follow your hand with your eyes.',
      'Return slowly and repeat.',
    ],
    cautions: 'Keep your knees together. $_stop',
    sets: 2,
    reps: 10,
    perDay: 1,
  ),
  ExerciseDef(
    id: 'back-wall-angel',
    muscles: [
      'm_serratus_anterior_muscle',
      'm_transverse_part_of_trapezius_muscle',
      'm_rhomboid_major_muscle',
    ],
    name: 'Wall angel',
    region: ExerciseRegion.upperBack,
    goal: 'Improves posture and shoulder mobility.',
    steps: [
      'Stand with your back and head against a wall, feet slightly forward.',
      'Raise your arms to the sides, elbows bent, against the wall.',
      'Slide them up and down like making a snow angel.',
      'Keep your lower back and head in light contact with the wall.',
    ],
    cautions: 'Reduce the range if your arms lift off the wall. $_stop',
    sets: 2,
    reps: 10,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  // Low back
  ExerciseDef(
    id: 'lb-pelvic-tilt',
    muscles: [
      'm_transversus_abdominis_muscle',
      'm_rectus_abdominis_muscle',
    ],
    name: 'Pelvic tilt',
    region: ExerciseRegion.lowBack,
    goal: 'Gentle low back mobility and lower tummy activation.',
    steps: [
      'Lie on your back with knees bent and feet flat.',
      'Tighten your tummy and flatten your lower back into the floor.',
      'Hold while breathing normally.',
      'Relax slowly.',
    ],
    cautions: 'Do not hold your breath or squeeze the buttocks hard. $_stop',
    sets: 2,
    reps: 10,
    holdSeconds: 5,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'lb-knee-to-chest',
    muscles: [
      'm_iliocostalis_lumborum_muscle',
      'm_longissimus_thoracis_muscle',
      'm_gluteus_maximus_muscle',
    ],
    name: 'Single knee to chest',
    region: ExerciseRegion.lowBack,
    goal: 'Gently stretches the low back and hip.',
    steps: [
      'Lie on your back with knees bent.',
      'Bring one knee toward your chest, holding behind the thigh.',
      'Keep the other foot flat on the floor.',
      'Hold, lower, and switch sides.',
    ],
    cautions: 'Stay within a comfortable range. $_stop',
    sets: 2,
    reps: 5,
    holdSeconds: 20,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'lb-cat-camel',
    muscles: [
      'm_multifidus_lumborum_muscle',
      'm_iliocostalis_lumborum_muscle',
      'm_rectus_abdominis_muscle',
    ],
    name: 'Cat and camel',
    region: ExerciseRegion.lowBack,
    goal: 'Mobilises the whole spine with gentle movement.',
    steps: [
      'Start on hands and knees, hands under shoulders, knees under hips.',
      'Slowly round your back up toward the ceiling.',
      'Then slowly let your tummy drop and lift your head slightly.',
      'Move smoothly between the two.',
    ],
    cautions: 'Move within a pain-free range. $_stop',
    sets: 2,
    reps: 10,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'lb-bridge',
    muscles: [
      'm_gluteus_maximus_muscle',
      'm_semitendinosus_muscle',
      'm_semimembranosus_muscle',
      'm_long_head_of_biceps_femoris',
    ],
    name: 'Glute bridge',
    region: ExerciseRegion.lowBack,
    goal:
        'Strengthens the buttocks and back of the hips, supporting the low back.',
    steps: [
      'Lie on your back, knees bent, feet flat and hip-width apart.',
      'Tighten your tummy and squeeze your buttocks.',
      'Lift your hips until shoulders, hips and knees form a line.',
      'Hold, then lower slowly.',
    ],
    cautions: 'Do not arch the lower back at the top. $_stop',
    sets: 3,
    reps: 10,
    holdSeconds: 3,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  ExerciseDef(
    id: 'lb-child-pose',
    muscles: [
      'm_iliocostalis_lumborum_muscle',
      'm_multifidus_lumborum_muscle',
      'm_latissimus_dorsi_muscle',
    ],
    name: 'Child pose stretch',
    region: ExerciseRegion.lowBack,
    goal: 'Relaxes and lengthens the low back.',
    steps: [
      'Kneel on the floor and sit back toward your heels.',
      'Reach your arms forward along the floor.',
      'Let your forehead rest down and breathe slowly.',
      'Hold, then come up slowly.',
    ],
    cautions: 'Skip if kneeling hurts the knees. $_stop',
    sets: 2,
    reps: 1,
    holdSeconds: 30,
    perDay: 2,
  ),
  // Hip
  ExerciseDef(
    id: 'hip-clamshell',
    muscles: [
      'm_gluteus_medius_muscle',
      'm_gluteus_minimus_muscle',
    ],
    name: 'Clamshell',
    region: ExerciseRegion.hip,
    goal: 'Strengthens the side of the hip.',
    steps: [
      'Lie on your side, hips and knees bent, feet together.',
      'Keep your feet touching and lift the top knee.',
      'Do not let your pelvis roll back.',
      'Lower slowly.',
    ],
    cautions: 'Keep the movement small and controlled. $_stop',
    sets: 3,
    reps: 12,
    perDay: 1,
  ),
  ExerciseDef(
    id: 'hip-side-leg-raise',
    muscles: [
      'm_gluteus_medius_muscle',
      'm_gluteus_minimus_muscle',
    ],
    name: 'Side-lying leg raise',
    region: ExerciseRegion.hip,
    goal: 'Strengthens the hip abductors used in walking.',
    steps: [
      'Lie on your side with the bottom knee bent for stability.',
      'Keep the top leg straight, toes pointing forward.',
      'Lift the leg to about hip height.',
      'Lower slowly.',
    ],
    cautions: 'Do not roll backward. $_stop',
    sets: 3,
    reps: 12,
    perDay: 1,
  ),
  ExerciseDef(
    id: 'hip-flexor-stretch',
    muscles: [
      'm_psoas_major',
      'm_iliacus_muscle',
      'm_rectus_femoris_muscle',
    ],
    name: 'Kneeling hip flexor stretch',
    region: ExerciseRegion.hip,
    goal: 'Stretches the front of the hip.',
    steps: [
      'Kneel on one knee, the other foot forward, on a cushion if needed.',
      'Tighten your tummy and tuck your pelvis under.',
      'Gently move your hips forward until you feel a stretch at the front of the hip.',
      'Hold and switch sides.',
    ],
    cautions: 'Do not arch the lower back. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 30,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'hip-piriformis-stretch',
    muscles: [
      'm_piriformis_muscle',
      'm_gluteus_maximus_muscle',
    ],
    name: 'Figure-four stretch',
    region: ExerciseRegion.hip,
    goal: 'Stretches the deep buttock and outer hip.',
    steps: [
      'Lie on your back, knees bent.',
      'Cross one ankle over the opposite knee.',
      'Pull the lower thigh gently toward your chest.',
      'Hold and switch sides.',
    ],
    cautions: 'Stretch gently. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 30,
    perDay: 2,
  ),
  // Knee
  ExerciseDef(
    id: 'knee-quad-set',
    muscles: [
      'm_vastus_medialis_muscle',
      'm_vastus_lateralis_muscle',
      'm_vastus_intermedius_muscle',
      'm_rectus_femoris_muscle',
    ],
    name: 'Quad set',
    region: ExerciseRegion.knee,
    goal:
        'Activates the thigh muscle, often used early after injury or surgery.',
    steps: [
      'Sit or lie with your leg straight and a small towel under the knee.',
      'Tighten the front thigh muscle, pressing the knee down into the towel.',
      'Hold the tightening.',
      'Relax slowly.',
    ],
    cautions: 'Do not hold your breath. $_stop',
    sets: 3,
    reps: 10,
    holdSeconds: 5,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'knee-straight-leg-raise',
    muscles: [
      'm_rectus_femoris_muscle',
      'm_vastus_medialis_muscle',
      'm_psoas_major',
      'm_iliacus_muscle',
    ],
    name: 'Straight leg raise',
    region: ExerciseRegion.knee,
    goal: 'Strengthens the thigh without bending the knee.',
    steps: [
      'Lie on your back, one knee bent, the other leg straight.',
      'Tighten the thigh of the straight leg.',
      'Lift it to the height of the bent knee.',
      'Lower slowly.',
    ],
    cautions: 'Keep the knee locked straight. $_stop',
    sets: 3,
    reps: 10,
    perDay: 1,
  ),
  ExerciseDef(
    id: 'knee-heel-slide',
    name: 'Heel slide',
    region: ExerciseRegion.knee,
    goal: 'Restores knee bending.',
    steps: [
      'Lie on your back with legs straight.',
      'Slide one heel toward your buttock, bending the knee.',
      'Go as far as comfortable and pause.',
      'Slide back to straight.',
    ],
    cautions: 'Go only to a mild stretch. $_stop',
    sets: 2,
    reps: 15,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'knee-mini-squat',
    muscles: [
      'm_vastus_medialis_muscle',
      'm_vastus_lateralis_muscle',
      'm_rectus_femoris_muscle',
      'm_gluteus_maximus_muscle',
    ],
    name: 'Mini squat',
    region: ExerciseRegion.knee,
    goal: 'Builds thigh and hip strength through a small, safe range.',
    steps: [
      'Stand with feet shoulder-width apart, holding a counter for balance.',
      'Bend your knees slightly, sending your hips back.',
      'Keep your knees in line with your toes.',
      'Straighten up slowly.',
    ],
    cautions: 'Do not let the knees fall inward. $_stop',
    sets: 3,
    reps: 10,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  ExerciseDef(
    id: 'knee-step-up',
    muscles: [
      'm_vastus_lateralis_muscle',
      'm_vastus_medialis_muscle',
      'm_gluteus_maximus_muscle',
      'm_gluteus_medius_muscle',
    ],
    name: 'Step-up',
    region: ExerciseRegion.knee,
    goal: 'Strengthens the leg for stairs and walking.',
    steps: [
      'Stand facing a low step, holding a rail if needed.',
      'Step up with one foot, then bring the other up.',
      'Step down slowly with the same leg that went up first.',
      'Repeat, then switch the leading leg.',
    ],
    cautions: 'Use a low step. $_stop',
    sets: 3,
    reps: 10,
    perDay: 1,
    level: ExerciseLevel.hard,
  ),
  ExerciseDef(
    id: 'knee-hamstring-stretch',
    muscles: [
      'm_semitendinosus_muscle',
      'm_semimembranosus_muscle',
      'm_long_head_of_biceps_femoris',
      'm_short_head_of_biceps_femoris',
    ],
    name: 'Hamstring stretch',
    region: ExerciseRegion.knee,
    goal: 'Stretches the back of the thigh.',
    steps: [
      'Sit on the edge of a chair, one leg straight with the heel on the floor.',
      'Keep your back straight and lean forward from the hips.',
      'Feel the stretch behind the thigh.',
      'Hold and switch legs.',
    ],
    cautions: 'Do not round the back. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 30,
    perDay: 2,
  ),
  // Ankle / foot
  ExerciseDef(
    id: 'ankle-alphabet',
    name: 'Ankle alphabet',
    region: ExerciseRegion.ankleFoot,
    goal: 'Gentle all-direction ankle movement.',
    steps: [
      'Sit with your leg raised or hanging free.',
      'Using your big toe like a pen, draw each letter of the alphabet in the air.',
      'Move from the ankle, not the knee.',
      'Repeat on the other foot.',
    ],
    cautions: 'Keep the movement comfortable. $_stop',
    sets: 2,
    reps: 1,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'ankle-calf-raise',
    muscles: [
      'm_medial_head_of_gastrocnemius',
      'm_lateral_head_of_gastrocnemius',
      'm_soleus_muscle',
    ],
    name: 'Calf raise',
    region: ExerciseRegion.ankleFoot,
    goal: 'Strengthens the calf and ankle.',
    steps: [
      'Stand holding a counter, feet hip-width apart.',
      'Rise up onto your toes.',
      'Pause at the top.',
      'Lower slowly.',
    ],
    cautions: 'Keep your weight over the big toe. $_stop',
    sets: 3,
    reps: 12,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  ExerciseDef(
    id: 'ankle-calf-stretch',
    muscles: [
      'm_medial_head_of_gastrocnemius',
      'm_lateral_head_of_gastrocnemius',
      'm_soleus_muscle',
    ],
    name: 'Wall calf stretch',
    region: ExerciseRegion.ankleFoot,
    goal: 'Stretches the calf muscle.',
    steps: [
      'Stand facing a wall, hands on it.',
      'Step one foot back, keeping the heel flat and knee straight.',
      'Lean forward until you feel the calf stretch.',
      'Hold and switch legs.',
    ],
    cautions: 'Keep the back heel down. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 30,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'foot-towel-scrunch',
    muscles: [
      'm_flexor_digitorum_brevis',
      'm_abductor_hallucis',
    ],
    name: 'Towel scrunch',
    region: ExerciseRegion.ankleFoot,
    goal: 'Strengthens the small muscles of the foot.',
    steps: [
      'Sit with your bare foot on a small towel.',
      'Curl your toes to scrunch the towel toward you.',
      'Release and repeat.',
    ],
    cautions: 'Stop if you get foot cramps. $_stop',
    sets: 3,
    reps: 10,
    perDay: 1,
  ),
  ExerciseDef(
    id: 'foot-plantar-fascia-stretch',
    muscles: [
      'm_plantar_aponeurosis',
      'm_flexor_digitorum_brevis',
    ],
    name: 'Plantar fascia stretch',
    region: ExerciseRegion.ankleFoot,
    goal: 'Gently stretches the thick band under the sole of the foot.',
    steps: [
      'Sit and cross the sore foot over your other knee.',
      'Pull your toes back toward your shin with your hand until you feel a stretch under the foot.',
      'Hold, then relax.',
    ],
    cautions: 'Stretch to a comfortable pull, not pain. $_stop',
    sets: 3,
    reps: 3,
    holdSeconds: 30,
    perDay: 3,
  ),
  // Core
  ExerciseDef(
    id: 'core-dead-bug',
    muscles: [
      'm_transversus_abdominis_muscle',
      'm_rectus_abdominis_muscle',
      'm_internal_abdominal_oblique_muscle',
    ],
    name: 'Dead bug',
    region: ExerciseRegion.core,
    goal: 'Trains core control while the arms and legs move.',
    steps: [
      'Lie on your back, hips and knees bent to 90 degrees, arms up.',
      'Flatten your lower back gently into the floor.',
      'Slowly lower the opposite arm and leg toward the floor.',
      'Return and switch sides.',
    ],
    cautions: 'Keep your lower back from arching. $_stop',
    sets: 3,
    reps: 10,
    perDay: 1,
    level: ExerciseLevel.hard,
  ),
  ExerciseDef(
    id: 'core-bird-dog',
    muscles: [
      'm_multifidus_lumborum_muscle',
      'm_longissimus_thoracis_muscle',
      'm_gluteus_maximus_muscle',
      'm_transversus_abdominis_muscle',
    ],
    name: 'Bird dog',
    region: ExerciseRegion.core,
    goal: 'Builds back and core stability.',
    steps: [
      'Start on hands and knees with a flat back.',
      'Tighten your tummy and reach one arm forward.',
      'Extend the opposite leg straight behind you.',
      'Hold, return, and switch sides.',
    ],
    cautions: 'Keep your hips level, do not twist. $_stop',
    sets: 3,
    reps: 8,
    holdSeconds: 5,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  ExerciseDef(
    id: 'core-plank',
    muscles: [
      'm_rectus_abdominis_muscle',
      'm_transversus_abdominis_muscle',
      'm_external_abdominal_oblique_muscle',
    ],
    name: 'Forearm plank',
    region: ExerciseRegion.core,
    goal: 'Builds endurance in the whole trunk.',
    steps: [
      'Lie face down, then prop yourself on your forearms, elbows under shoulders.',
      'Lift your body so it forms a straight line from head to heels.',
      'Tighten your tummy and hold.',
      'Lower gently.',
    ],
    cautions: 'Do not let the hips sag or lift. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 20,
    perDay: 1,
    level: ExerciseLevel.hard,
  ),
  ExerciseDef(
    id: 'core-side-plank-knees',
    muscles: [
      'm_external_abdominal_oblique_muscle',
      'm_internal_abdominal_oblique_muscle',
      'm_quadratus_lumborum_muscle',
      'm_gluteus_medius_muscle',
    ],
    name: 'Side plank (knees bent)',
    region: ExerciseRegion.core,
    goal: 'Strengthens the side of the trunk.',
    steps: [
      'Lie on your side, knees bent, propped on your forearm.',
      'Lift your hips so your body is in a line from shoulder to knee.',
      'Hold, breathing normally.',
      'Lower gently and switch sides.',
    ],
    cautions: 'Keep the shoulder away from the ear. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 15,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  // Balance
  ExerciseDef(
    id: 'bal-single-leg-stance',
    muscles: [
      'm_gluteus_medius_muscle',
      'm_tibialis_anterior_muscle',
    ],
    name: 'Single-leg stance',
    region: ExerciseRegion.balance,
    goal: 'Improves balance and ankle control.',
    steps: [
      'Stand next to a counter or wall for safety.',
      'Lift one foot slightly off the floor.',
      'Stand tall and hold the position.',
      'Switch legs.',
    ],
    cautions: 'Always keep a support within reach. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 20,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'bal-tandem-stance',
    name: 'Heel-to-toe stance',
    region: ExerciseRegion.balance,
    goal: 'Challenges balance with a narrow base.',
    steps: [
      'Stand near a counter, one foot directly in front of the other, heel touching toes.',
      'Stand tall and look ahead.',
      'Hold as steady as you can.',
      'Switch which foot is in front.',
    ],
    cautions: 'Have a support within reach. $_stop',
    sets: 3,
    reps: 1,
    holdSeconds: 20,
    perDay: 2,
  ),
  ExerciseDef(
    id: 'bal-sit-to-stand',
    muscles: [
      'm_vastus_lateralis_muscle',
      'm_vastus_medialis_muscle',
      'm_gluteus_maximus_muscle',
    ],
    name: 'Sit to stand',
    region: ExerciseRegion.balance,
    goal: 'Builds leg strength and confidence getting up from a chair.',
    steps: [
      'Sit near the front of a sturdy chair, feet flat.',
      'Lean forward slightly and stand up without using your hands if you can.',
      'Stand fully upright.',
      'Sit back down slowly.',
    ],
    cautions: 'Use a firm chair that will not slide. $_stop',
    sets: 3,
    reps: 10,
    perDay: 1,
    level: ExerciseLevel.medium,
  ),
  // Breathing
  ExerciseDef(
    id: 'breath-diaphragmatic',
    muscles: [
      'm_diaphragm',
    ],
    name: 'Diaphragmatic breathing',
    region: ExerciseRegion.breathing,
    goal: 'Teaches relaxed belly breathing.',
    steps: [
      'Lie or sit comfortably, one hand on your chest and one on your belly.',
      'Breathe in slowly through your nose so the belly hand rises.',
      'Keep the chest hand still.',
      'Breathe out slowly through pursed lips.',
    ],
    cautions: 'Do not force the breath. $_stop',
    sets: 2,
    reps: 10,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'breath-pursed-lip',
    name: 'Pursed-lip breathing',
    region: ExerciseRegion.breathing,
    goal: 'Slows the breath and eases breathlessness.',
    steps: [
      'Sit relaxed with shoulders down.',
      'Breathe in gently through your nose for about 2 seconds.',
      'Purse your lips as if blowing out a candle.',
      'Breathe out slowly for about 4 seconds.',
    ],
    cautions: 'Do not blow hard. $_stop',
    sets: 2,
    reps: 10,
    perDay: 3,
  ),
  ExerciseDef(
    id: 'breath-rib-expansion',
    muscles: [
      'm_diaphragm',
      'm_external_intercostal_muscles',
    ],
    name: 'Lateral rib breathing',
    region: ExerciseRegion.breathing,
    goal: 'Encourages the lower ribs to expand.',
    steps: [
      'Sit tall with your hands on the sides of your lower ribs.',
      'Breathe in and feel your ribs widen into your hands.',
      'Breathe out and feel them draw in.',
      'Repeat slowly.',
    ],
    cautions: 'Keep your shoulders relaxed. $_stop',
    sets: 2,
    reps: 8,
    perDay: 2,
  ),
];
