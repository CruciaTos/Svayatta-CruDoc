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
];
