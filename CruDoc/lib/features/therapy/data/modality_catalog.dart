// The electrotherapy and thermal modalities a physiotherapy clinic applies,
// and the settings that have to be recorded with each one.
//
// Why the parameters matter enough to have their own catalogue: "gave the
// patient ultrasound" is not a record of treatment. 1 MHz continuous at
// 1.5 W/cm² is a different intervention from 3 MHz pulsed at 0.5, and when
// a patient is reassessed six weeks later, or asks what was done to them,
// the settings are the only thing that answers it. A log without
// parameters cannot be repeated, progressed or defended.
//
// Values offered as [ModalityParam.presets] are the commonly used settings,
// there to save typing. They are not recommendations and the physio can
// enter anything; nothing in this file is applied automatically and no
// value is ever filled in by default.
//
// **The cautions on each modality are not a safety system.** They are the
// standard contraindications from physiotherapy electrotherapy teaching,
// written down so the person at the machine sees them at the moment of
// setting it. They are not exhaustive, they do not replace the physio's own
// screening, and the app never blocks an application on them. This whole
// file — the parameter ranges and the cautions alike — needs a
// physiotherapist's review before a clinic relies on it.

/// How one setting is entered.
enum ModalityParamKind {
  /// One of a fixed set of named settings (waveform, duty cycle).
  choice,

  /// A typed figure, with [ModalityParam.unit] shown beside it.
  number,
}

/// One setting on a machine.
class ModalityParam {
  const ModalityParam(
    this.id,
    this.label,
    this.kind, {
    this.unit = '',
    this.presets = const [],
    this.help = '',
  });

  final String id;
  final String label;
  final ModalityParamKind kind;

  /// Shown after the value, e.g. `Hz`, `W/cm²`, `mA`. Empty for a choice.
  final String unit;

  /// Quick-tap values. For a [ModalityParamKind.choice] these are the only
  /// values; for a number they are shortcuts and anything may be typed.
  final List<String> presets;

  /// A word on what the setting does, shown under the field.
  final String help;

  bool get isChoice => kind == ModalityParamKind.choice;
}

/// One modality, with the settings that have to be logged for it.
class ModalityDef {
  const ModalityDef({
    required this.id,
    required this.name,
    required this.short,
    required this.params,
    required this.cautions,
    this.minutePresets = const ['10', '15', '20'],
  });

  final String id;

  /// What it is called in full, e.g. "Interferential therapy".
  final String name;

  /// What a physio writes in a note, e.g. "IFT". Used on cards and in the
  /// report, where the full name would crowd out the settings.
  final String short;

  final List<ModalityParam> params;

  /// Standard contraindications and precautions, shown while logging.
  final List<String> cautions;

  /// Common treatment times, as shortcuts.
  final List<String> minutePresets;

  ModalityParam? param(String id) {
    for (final p in params) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Electrical nerve and muscle stimulation cautions, shared by the modalities
/// that pass a current through the patient. Kept in one place so they cannot
/// drift apart between TENS, IFT and NMES, where they are the same cautions.
const List<String> _electricalCautions = [
  'Cardiac pacemaker or any implanted electrical device',
  'Over the front of the neck or the carotid sinus',
  'Over the abdomen or low back in pregnancy',
  'Over broken skin, or skin with reduced sensation',
  'Directly over a known malignancy',
  'Over the chest in known cardiac disease',
];

/// The catalogue, in the order a clinic's machines usually get reached for.
const List<ModalityDef> kModalities = [
  ModalityDef(
    id: 'tens',
    name: 'Transcutaneous electrical nerve stimulation',
    short: 'TENS',
    minutePresets: ['20', '30', '45'],
    params: [
      ModalityParam(
        'mode',
        'Mode',
        ModalityParamKind.choice,
        presets: [
          'Conventional (high rate)',
          'Acupuncture-like (low rate)',
          'Burst',
          'Modulated',
        ],
      ),
      ModalityParam(
        'frequency',
        'Frequency',
        ModalityParamKind.number,
        unit: 'Hz',
        presets: ['2', '10', '80', '100', '150'],
      ),
      ModalityParam(
        'pulseWidth',
        'Pulse width',
        ModalityParamKind.number,
        unit: 'µs',
        presets: ['50', '100', '200', '250'],
      ),
      ModalityParam(
        'intensity',
        'Intensity',
        ModalityParamKind.number,
        unit: 'mA',
        help: 'Set to a strong but comfortable tingle, never to pain.',
      ),
    ],
    cautions: _electricalCautions,
  ),
  ModalityDef(
    id: 'ift',
    name: 'Interferential therapy',
    short: 'IFT',
    minutePresets: ['10', '15', '20'],
    params: [
      ModalityParam(
        'carrier',
        'Carrier frequency',
        ModalityParamKind.number,
        unit: 'Hz',
        presets: ['2000', '4000'],
      ),
      ModalityParam(
        'beat',
        'Beat frequency (AMF)',
        ModalityParamKind.number,
        unit: 'Hz',
        presets: ['10', '50', '100'],
      ),
      ModalityParam(
        'sweep',
        'Sweep',
        ModalityParamKind.choice,
        presets: ['None', '10–50 Hz', '80–150 Hz', '1–100 Hz'],
      ),
      ModalityParam(
        'intensity',
        'Intensity',
        ModalityParamKind.number,
        unit: 'mA',
      ),
    ],
    cautions: _electricalCautions,
  ),
  ModalityDef(
    id: 'ultrasound',
    name: 'Therapeutic ultrasound',
    short: 'US',
    minutePresets: ['5', '8', '10'],
    params: [
      ModalityParam(
        'frequency',
        'Frequency',
        ModalityParamKind.choice,
        presets: ['1 MHz (deeper)', '3 MHz (superficial)'],
      ),
      ModalityParam(
        'intensity',
        'Intensity',
        ModalityParamKind.number,
        unit: 'W/cm²',
        presets: ['0.5', '0.8', '1.0', '1.5', '2.0'],
      ),
      ModalityParam(
        'duty',
        'Duty cycle',
        ModalityParamKind.choice,
        presets: ['Continuous', 'Pulsed 50%', 'Pulsed 20%'],
        help: 'Pulsed for acute or thermally sensitive tissue.',
      ),
    ],
    cautions: [
      'Over a malignancy',
      'Over the eye, or over the pregnant uterus',
      'Over growth plates in a child',
      'Over the heart, or over a pacemaker',
      'Over a deep vein thrombosis or thrombophlebitis',
      'Over cemented or plastic joint components',
      'Over ischaemic tissue, or tissue with reduced sensation',
      'Over the spinal cord after laminectomy',
    ],
  ),
  ModalityDef(
    id: 'swd',
    name: 'Short wave diathermy',
    short: 'SWD',
    minutePresets: ['15', '20'],
    params: [
      ModalityParam(
        'mode',
        'Mode',
        ModalityParamKind.choice,
        presets: ['Continuous', 'Pulsed'],
      ),
      ModalityParam(
        'dose',
        'Dose',
        ModalityParamKind.choice,
        presets: [
          'I — no warmth',
          'II — mild warmth',
          'III — comfortable warmth',
          'IV — vigorous warmth',
        ],
        help: 'Graded on what the patient reports, not on the dial.',
      ),
    ],
    cautions: [
      'Any metal implant, plate or intrauterine device in the field',
      'Cardiac pacemaker or implanted electrical device',
      'Pregnancy',
      'Reduced or absent sensation',
      'Malignancy, or active tuberculosis',
      'Wet dressings or damp clothing in the field',
      'Over the eyes, or over contact lenses',
      'Acute inflammation with bleeding',
    ],
  ),
  ModalityDef(
    id: 'laser',
    name: 'Low level laser therapy',
    short: 'LASER',
    minutePresets: ['3', '5', '8'],
    params: [
      ModalityParam(
        'wavelength',
        'Wavelength',
        ModalityParamKind.number,
        unit: 'nm',
        presets: ['650', '808', '850', '904'],
      ),
      ModalityParam(
        'dose',
        'Dose',
        ModalityParamKind.number,
        unit: 'J/cm²',
        presets: ['1', '2', '4', '6'],
      ),
      ModalityParam(
        'technique',
        'Technique',
        ModalityParamKind.choice,
        presets: ['Contact point', 'Grid scan', 'Non-contact'],
      ),
    ],
    cautions: [
      'Over or near the eyes — eye protection for patient and physio',
      'Over a malignancy',
      'Over the pregnant uterus',
      'Over the thyroid gland',
      'On a patient taking photosensitising medication',
      'Over active haemorrhage',
    ],
  ),
  ModalityDef(
    id: 'nmes',
    name: 'Neuromuscular electrical stimulation',
    short: 'NMES',
    minutePresets: ['10', '15', '20'],
    params: [
      ModalityParam(
        'frequency',
        'Frequency',
        ModalityParamKind.number,
        unit: 'Hz',
        presets: ['35', '50', '75'],
      ),
      ModalityParam(
        'onOff',
        'On : off ratio',
        ModalityParamKind.choice,
        presets: ['1:1', '1:3', '1:5'],
        help: 'Longer rest for a muscle that fatigues quickly.',
      ),
      ModalityParam(
        'intensity',
        'Intensity',
        ModalityParamKind.number,
        unit: 'mA',
        help: 'To a visible, tolerable contraction.',
      ),
    ],
    cautions: _electricalCautions,
  ),
  ModalityDef(
    id: 'traction',
    name: 'Mechanical traction',
    short: 'Traction',
    minutePresets: ['10', '15', '20'],
    params: [
      ModalityParam(
        'region',
        'Region',
        ModalityParamKind.choice,
        presets: ['Cervical', 'Lumbar'],
      ),
      ModalityParam(
        'mode',
        'Mode',
        ModalityParamKind.choice,
        presets: ['Static', 'Intermittent'],
      ),
      ModalityParam('weight', 'Pull', ModalityParamKind.number, unit: 'kg'),
      ModalityParam('hold', 'Hold', ModalityParamKind.number, unit: 's'),
      ModalityParam('rest', 'Rest', ModalityParamKind.number, unit: 's'),
    ],
    cautions: [
      'Spinal instability, fracture or recent spinal surgery',
      'Signs of cord compression or cauda equina',
      'Vertebrobasilar insufficiency (cervical)',
      'Rheumatoid arthritis of the cervical spine',
      'Osteoporosis, or malignancy in the spine',
      'Pregnancy (lumbar)',
      'Acute inflammatory arthritis',
    ],
  ),
  ModalityDef(
    id: 'hotpack',
    name: 'Moist heat pack',
    short: 'Hot pack',
    minutePresets: ['15', '20'],
    params: [
      ModalityParam(
        'layers',
        'Towel layers',
        ModalityParamKind.number,
        presets: ['6', '8'],
        help: 'Between pack and skin. Check the skin partway through.',
      ),
    ],
    cautions: [
      'Reduced or absent sensation',
      'Acute injury still bleeding or swelling',
      'Poor arterial circulation',
      'Over a recent skin graft or fragile skin',
      'A patient who cannot report that it is too hot',
    ],
  ),
  ModalityDef(
    id: 'wax',
    name: 'Paraffin wax bath',
    short: 'Wax',
    minutePresets: ['15', '20'],
    params: [
      ModalityParam(
        'method',
        'Method',
        ModalityParamKind.choice,
        presets: ['Dip and wrap', 'Dip and immerse', 'Painting'],
      ),
    ],
    cautions: [
      'Open wounds or broken skin',
      'Any skin infection',
      'Reduced or absent sensation',
      'Known allergy or skin reaction to the wax',
      'Poor arterial circulation',
    ],
  ),
  ModalityDef(
    id: 'cryo',
    name: 'Cryotherapy',
    short: 'Cryo',
    minutePresets: ['10', '15'],
    params: [
      ModalityParam(
        'method',
        'Method',
        ModalityParamKind.choice,
        presets: ['Cold pack', 'Ice massage', 'Ice bath', 'Vapocoolant spray'],
      ),
    ],
    cautions: [
      'Cold intolerance, cold urticaria or cryoglobulinaemia',
      "Raynaud's phenomenon",
      'Arterial insufficiency',
      'Reduced or absent sensation',
      'Directly over a superficial peripheral nerve',
      'Over a recent skin graft or fragile skin',
    ],
  ),
];

/// The modality with this id, or null when a record names one the catalogue
/// no longer has.
///
/// Null rather than a fallback, so a record from a removed modality shows as
/// what it is instead of being relabelled as something else.
ModalityDef? modalityById(String id) {
  for (final m in kModalities) {
    if (m.id == id) return m;
  }
  return null;
}
