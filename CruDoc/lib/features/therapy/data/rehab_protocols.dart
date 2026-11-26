/// One exercise in a protocol, with optional dose overrides. Anything left
/// null uses the library exercise's own default dose.
class ProtocolItem {
  const ProtocolItem(
    this.exerciseId, {
    this.sets,
    this.reps,
    this.holdSeconds,
    this.perDay,
  });

  final String exerciseId;
  final int? sets;
  final int? reps;
  final int? holdSeconds;
  final int? perDay;
}

/// A ready-made starting program. Always a starting point: the physio adjusts
/// it to the patient.
class RehabProtocol {
  const RehabProtocol({
    required this.id,
    required this.name,
    required this.description,
    required this.items,
  });

  final String id;
  final String name;
  final String description;
  final List<ProtocolItem> items;
}

const String kProtocolDisclaimer = 'Starting point - adjust to the patient.';

const List<RehabProtocol> kRehabProtocols = [
  RehabProtocol(
    id: 'frozen-shoulder-early',
    name: 'Frozen shoulder (early)',
    description: 'Gentle, pain-limited movement to keep the shoulder mobile.',
    items: [
      ProtocolItem('shoulder-pendulum', perDay: 3),
      ProtocolItem('shoulder-wall-slide', sets: 2, reps: 8, perDay: 2),
      ProtocolItem('shoulder-cross-body-stretch', sets: 2, perDay: 2),
      ProtocolItem('shoulder-scap-squeeze', sets: 2, reps: 10, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'rotator-cuff-impingement',
    name: 'Rotator cuff / shoulder impingement',
    description: 'Cuff and shoulder blade control with posture work.',
    items: [
      ProtocolItem('shoulder-scap-squeeze', perDay: 2),
      ProtocolItem('shoulder-ext-rotation', sets: 2, reps: 10),
      ProtocolItem('shoulder-wall-slide', sets: 2, reps: 10, perDay: 1),
      ProtocolItem('shoulder-cross-body-stretch', sets: 2),
      ProtocolItem('back-thoracic-extension', sets: 2, reps: 8),
    ],
  ),
  RehabProtocol(
    id: 'neck-desk-posture',
    name: 'Neck pain / desk posture',
    description: 'Neck mobility, deep neck muscles and upper back posture.',
    items: [
      ProtocolItem('neck-chin-tuck'),
      ProtocolItem('neck-side-stretch', sets: 2, holdSeconds: 20, perDay: 3),
      ProtocolItem('neck-rotation', sets: 2, reps: 8, perDay: 3),
      ProtocolItem('shoulder-scap-squeeze', sets: 2, reps: 10, perDay: 3),
      ProtocolItem('back-thoracic-extension', sets: 2, reps: 8, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'low-back-acute-settling',
    name: 'Low back pain (acute, settling)',
    description: 'Gentle movement and light core activation as pain eases.',
    items: [
      ProtocolItem('lb-pelvic-tilt', sets: 2, reps: 10, perDay: 3),
      ProtocolItem('lb-knee-to-chest', sets: 2, reps: 8, perDay: 3),
      ProtocolItem('lb-cat-camel', sets: 2, reps: 8, perDay: 2),
      ProtocolItem('lb-bridge', sets: 2, reps: 8, perDay: 1),
      ProtocolItem('lb-child-pose', sets: 2, reps: 3, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'knee-oa-post-tkr',
    name: 'Knee OA / early post-knee-replacement',
    description:
        'Knee movement and thigh strength; follow the surgeon\'s limits.',
    items: [
      ProtocolItem(
        'knee-quad-set',
        sets: 3,
        reps: 10,
        holdSeconds: 5,
        perDay: 3,
      ),
      ProtocolItem('knee-heel-slide', sets: 2, reps: 10, perDay: 3),
      ProtocolItem('knee-straight-leg-raise', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('knee-hamstring-stretch', sets: 2, perDay: 2),
      ProtocolItem('bal-sit-to-stand', sets: 2, reps: 8, perDay: 1),
    ],
  ),
  RehabProtocol(
    id: 'acl-early',
    name: 'Post-ACL (early phase)',
    description: 'Early range of motion and quadriceps activation.',
    items: [
      ProtocolItem(
        'knee-quad-set',
        sets: 3,
        reps: 10,
        holdSeconds: 5,
        perDay: 3,
      ),
      ProtocolItem('knee-heel-slide', sets: 2, reps: 10, perDay: 3),
      ProtocolItem('knee-straight-leg-raise', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('knee-hamstring-stretch', sets: 2, perDay: 2),
      ProtocolItem('hip-side-leg-raise', sets: 2, reps: 10, perDay: 1),
    ],
  ),
  RehabProtocol(
    id: 'ankle-sprain',
    name: 'Ankle sprain recovery',
    description: 'Motion first, then calf strength and balance.',
    items: [
      ProtocolItem('ankle-alphabet', sets: 2, reps: 1, perDay: 3),
      ProtocolItem('ankle-calf-stretch', sets: 2, perDay: 2),
      ProtocolItem('ankle-calf-raise', sets: 2, reps: 10, perDay: 1),
      ProtocolItem(
        'bal-single-leg-stance',
        sets: 3,
        holdSeconds: 20,
        perDay: 1,
      ),
    ],
  ),
  RehabProtocol(
    id: 'plantar-fasciitis',
    name: 'Plantar fasciitis',
    description: 'Stretching of the sole and calf, with foot strengthening.',
    items: [
      ProtocolItem('foot-plantar-fascia-stretch'),
      ProtocolItem('ankle-calf-stretch', sets: 3, perDay: 2),
      ProtocolItem('foot-towel-scrunch', sets: 2, reps: 10),
      ProtocolItem('ankle-calf-raise', sets: 2, reps: 10, perDay: 1),
    ],
  ),

  // -------------------------------------------------------------------
  // The common presentations the first eight did not cover. Each one is
  // built only from exercises already in the library, so a protocol can
  // never name an exercise the picker cannot find — a test checks that.
  //
  // Every one of these is a starting point, as [kProtocolDisclaimer] says
  // on screen. The doses are conservative and the ordering is the one a
  // physio would usually teach in: mobility or activation first, then
  // loading, then balance.
  // -------------------------------------------------------------------
  RehabProtocol(
    id: 'tennis-elbow',
    name: 'Tennis elbow (lateral)',
    description:
        'Loading the wrist extensors slowly, with the stretches that let '
        'them tolerate it.',
    items: [
      ProtocolItem('wrist-extensor-stretch', sets: 3, perDay: 2),
      ProtocolItem('elbow-eccentric-curl', sets: 3, reps: 12),
      ProtocolItem('wrist-grip-squeeze', sets: 2, reps: 10),
      ProtocolItem('wrist-pronation-supination', sets: 2, reps: 10),
    ],
  ),
  RehabProtocol(
    id: 'golfers-elbow',
    name: "Golfer's elbow (medial)",
    description: 'The same approach as tennis elbow, on the flexor side.',
    items: [
      ProtocolItem('wrist-flexor-stretch', sets: 3, perDay: 2),
      ProtocolItem('wrist-grip-squeeze', sets: 3, reps: 10),
      ProtocolItem('elbow-bicep-curl', sets: 2, reps: 12),
      ProtocolItem('wrist-pronation-supination', sets: 2, reps: 10),
    ],
  ),
  RehabProtocol(
    id: 'wrist-overuse',
    name: 'Wrist overuse / keyboard strain',
    description: 'Gentle range and balanced stretching for both sides.',
    items: [
      ProtocolItem('wrist-flexor-stretch', sets: 2, perDay: 3),
      ProtocolItem('wrist-extensor-stretch', sets: 2, perDay: 3),
      ProtocolItem('wrist-pronation-supination', sets: 2, reps: 10, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'cervical-radiculopathy',
    name: 'Neck with arm symptoms (settling)',
    description:
        'Deep neck control and scapular support once the arm symptoms are '
        'settling. Keep everything within a pain-free range.',
    items: [
      ProtocolItem('neck-chin-tuck', sets: 2, reps: 8, perDay: 3),
      ProtocolItem('neck-scapular-setting', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('neck-isometric-flexion', sets: 2, reps: 5),
      ProtocolItem('back-wall-angel', sets: 2, reps: 8),
    ],
  ),
  RehabProtocol(
    id: 'tension-headache',
    name: 'Tension headache / tight upper neck',
    description: 'Easing the upper neck and shoulders, with slower breathing.',
    items: [
      ProtocolItem('neck-side-stretch', sets: 2, perDay: 3),
      ProtocolItem('neck-scapular-setting', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('back-open-book', sets: 2, reps: 8),
      ProtocolItem('breath-diaphragmatic', perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'thoracic-desk-stiffness',
    name: 'Mid-back stiffness (desk work)',
    description: 'Opening a stiff mid-back and resetting shoulder position.',
    items: [
      ProtocolItem('back-thoracic-extension', sets: 2, reps: 8, perDay: 2),
      ProtocolItem('back-open-book', sets: 2, reps: 8),
      ProtocolItem('back-wall-angel', sets: 2, reps: 10),
      ProtocolItem('neck-chin-tuck', sets: 2, reps: 8, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'low-back-chronic',
    name: 'Low back pain (chronic, strengthening)',
    description:
        'Trunk control and hip strength for a back that has settled but '
        'keeps recurring.',
    items: [
      ProtocolItem('lb-pelvic-tilt', sets: 2, reps: 10),
      ProtocolItem('lb-bridge', sets: 3, reps: 10),
      ProtocolItem('core-dead-bug', sets: 2, reps: 8),
      ProtocolItem('core-bird-dog', sets: 2, reps: 8),
      ProtocolItem('hip-clamshell', sets: 2, reps: 12),
    ],
  ),
  RehabProtocol(
    id: 'sacroiliac-pain',
    name: 'Sacroiliac / pelvic girdle pain',
    description: 'Gentle pelvic control and hip stability, nothing forced.',
    items: [
      ProtocolItem('lb-pelvic-tilt', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('hip-clamshell', sets: 2, reps: 12),
      ProtocolItem('lb-bridge', sets: 2, reps: 8),
      ProtocolItem('core-dead-bug', sets: 2, reps: 8),
    ],
  ),
  RehabProtocol(
    id: 'hip-oa',
    name: 'Hip osteoarthritis',
    description: 'Keeping the hip moving and the muscles around it working.',
    items: [
      ProtocolItem('hip-clamshell', sets: 2, reps: 12),
      ProtocolItem('hip-side-leg-raise', sets: 2, reps: 12),
      ProtocolItem('hip-flexor-stretch', sets: 2, perDay: 2),
      ProtocolItem('bal-sit-to-stand', sets: 2, reps: 8),
    ],
  ),
  RehabProtocol(
    id: 'gluteal-tendinopathy',
    name: 'Gluteal tendinopathy / outer hip pain',
    description:
        'Loading the outer hip without compressing it. Avoid crossing the '
        'legs and lying on that side.',
    items: [
      ProtocolItem('hip-clamshell', sets: 3, reps: 12),
      ProtocolItem('hip-side-leg-raise', sets: 2, reps: 10),
      ProtocolItem('bal-single-leg-stance', sets: 2, holdSeconds: 20),
      ProtocolItem('lb-bridge', sets: 2, reps: 10),
    ],
  ),
  RehabProtocol(
    id: 'patellofemoral-pain',
    name: 'Kneecap pain (patellofemoral)',
    description:
        'Quadriceps and hip strength, kept inside the range that does not '
        'provoke the kneecap.',
    items: [
      ProtocolItem('knee-quad-set', sets: 3, reps: 10, perDay: 2),
      ProtocolItem('knee-mini-squat', sets: 2, reps: 10),
      ProtocolItem('hip-clamshell', sets: 2, reps: 12),
      ProtocolItem('knee-hamstring-stretch', sets: 2, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'hamstring-strain',
    name: 'Hamstring strain (settling)',
    description:
        'Range first, then gentle loading. Progress only when the previous '
        'stage is pain-free.',
    items: [
      ProtocolItem('knee-hamstring-stretch', sets: 2, perDay: 2),
      ProtocolItem('knee-straight-leg-raise', sets: 2, reps: 10),
      ProtocolItem('lb-bridge', sets: 3, reps: 10),
    ],
  ),
  RehabProtocol(
    id: 'achilles-tendinopathy',
    name: 'Achilles tendinopathy',
    description:
        'Slow calf loading, which is the part that changes a tendon. '
        'Expect it to be slow.',
    items: [
      ProtocolItem('ankle-calf-stretch', sets: 2, perDay: 2),
      ProtocolItem('ankle-heel-raise', sets: 3, reps: 12, perDay: 1),
      ProtocolItem('foot-plantar-fascia-stretch', sets: 2),
    ],
  ),
  RehabProtocol(
    id: 'ankle-instability',
    name: 'Ankle instability (recurrent sprains)',
    description:
        'Strength in both directions plus balance, which is what stops the '
        'next sprain.',
    items: [
      ProtocolItem('ankle-eversion-band', sets: 3, reps: 12),
      ProtocolItem('ankle-inversion-band', sets: 3, reps: 12),
      ProtocolItem('bal-single-leg-stance', sets: 3, holdSeconds: 20),
      ProtocolItem('bal-tandem-stance', sets: 2, holdSeconds: 20),
      ProtocolItem('foot-toe-spread', sets: 2, reps: 10),
    ],
  ),
  RehabProtocol(
    id: 'falls-prevention',
    name: 'Falls prevention (older adult)',
    description:
        'Strength and balance together. Everything within reach of a '
        'counter or chair.',
    items: [
      ProtocolItem('bal-sit-to-stand', sets: 2, reps: 10),
      ProtocolItem('bal-weight-shift', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('ankle-heel-raise', sets: 2, reps: 10),
      ProtocolItem('bal-tandem-stance', sets: 3, holdSeconds: 20),
      ProtocolItem('bal-head-turns', sets: 2, reps: 8),
    ],
  ),
  RehabProtocol(
    id: 'deconditioning-breathing',
    name: 'Breathlessness and deconditioning',
    description:
        'Breathing control first, then gentle whole-body work. Stop at '
        'moderate breathlessness, not severe.',
    items: [
      ProtocolItem('breath-diaphragmatic', perDay: 3),
      ProtocolItem('breath-pursed-lip', sets: 2, reps: 8, perDay: 3),
      ProtocolItem('breath-thoracic-expansion', sets: 2, reps: 8, perDay: 2),
      ProtocolItem('bal-sit-to-stand', sets: 2, reps: 8),
    ],
  ),
  RehabProtocol(
    id: 'shoulder-post-op-protected',
    name: 'Shoulder, early protected phase',
    description:
        'Only what is allowed while the repair is protected. Follow the '
        'surgeon\'s range limits over anything here.',
    items: [
      ProtocolItem('shoulder-pendulum', perDay: 3),
      ProtocolItem('shoulder-wall-slide', sets: 2, reps: 8, perDay: 2),
      ProtocolItem('neck-scapular-setting', sets: 2, reps: 10),
    ],
  ),

  // The last five, now that the exercise library has the loading and hand
  // work these need.
  RehabProtocol(
    id: 'frozen-shoulder-later',
    name: 'Frozen shoulder (thawing)',
    description:
        'Once the painful stage has settled: range first, then loading. '
        'Progress is measured in months with this one.',
    items: [
      ProtocolItem('shoulder-assisted-flexion', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('shoulder-towel-stretch', sets: 3, perDay: 2),
      ProtocolItem('shoulder-sleeper-stretch', sets: 2, perDay: 2),
      ProtocolItem('shoulder-ext-rotation', sets: 3, reps: 12),
      ProtocolItem('shoulder-band-row', sets: 3, reps: 12),
    ],
  ),
  RehabProtocol(
    id: 'hip-replacement-early',
    name: 'Hip replacement, early',
    description:
        'Circulation and gentle strength in the first weeks. Follow the '
        "surgeon's movement precautions over anything here — commonly no "
        'crossing the legs, no bending the hip past a right angle and no '
        'turning the leg inward.',
    items: [
      ProtocolItem('ankle-alphabet', perDay: 4),
      ProtocolItem('knee-quad-set', sets: 3, reps: 10, perDay: 3),
      ProtocolItem('hip-band-abduction-standing', sets: 2, reps: 10),
      ProtocolItem('hip-standing-extension-band', sets: 2, reps: 10),
      ProtocolItem('bal-sit-to-stand', sets: 2, reps: 8, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'carpal-tunnel',
    name: 'Carpal tunnel / median nerve at the wrist',
    description:
        'Nerve glides plus tendon and thumb work. Splinting at night and '
        'load management matter as much as the exercises.',
    items: [
      ProtocolItem('neck-median-nerve-glide', sets: 2, reps: 10, perDay: 2),
      ProtocolItem('wrist-tendon-glides', sets: 3, reps: 5, perDay: 3),
      ProtocolItem('wrist-thumb-opposition', sets: 2, reps: 5, perDay: 2),
      ProtocolItem('wrist-flexor-stretch', sets: 2, perDay: 2),
      ProtocolItem('wrist-extensor-stretch', sets: 2, perDay: 2),
    ],
  ),
  RehabProtocol(
    id: 'shin-splints',
    name: 'Shin pain (medial tibial stress)',
    description:
        'Calf and foot loading with hip control, alongside cutting back the '
        'running volume that brought it on.',
    items: [
      ProtocolItem('ankle-calf-stretch', sets: 2, perDay: 2),
      ProtocolItem('ankle-heel-raise', sets: 3, reps: 15),
      ProtocolItem('ankle-dorsiflexion-band', sets: 3, reps: 15),
      ProtocolItem('foot-short-foot', sets: 3, reps: 10, perDay: 2),
      ProtocolItem('hip-clamshell', sets: 2, reps: 12),
    ],
  ),
  RehabProtocol(
    id: 'groin-strain',
    name: 'Groin strain (adductor)',
    description:
        'Isometric inner thigh work first, which is usually comfortable '
        'early, then range and hip strength around it.',
    items: [
      ProtocolItem('hip-adductor-squeeze', sets: 3, reps: 10, perDay: 2),
      ProtocolItem('hip-adductor-stretch', sets: 2, perDay: 2),
      ProtocolItem('hip-clamshell', sets: 2, reps: 12),
      ProtocolItem('lb-bridge', sets: 3, reps: 10),
    ],
  ),
];
