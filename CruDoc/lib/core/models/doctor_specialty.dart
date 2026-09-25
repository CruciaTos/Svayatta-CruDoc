import 'package:flutter/material.dart';

/// All supported doctor specialties in CruDoc.
enum DoctorSpecialtyType {
  generalPhysician,
  cardiologist,
  pediatrician,
  dentist,
  dermatologist,
  orthopedic,
  gynecologist,
  psychiatrist,
  physiotherapy,
  homeopathy,

  /// Dental sub-specialty: Oral & Maxillofacial Radiologist (reads scans).
  oralRadiologist,

  /// Dental sub-specialty: Periodontist (gum health, scaling, SRP).
  periodontist,

  /// Dental sub-specialty: Endodontist (root canal therapy).
  endodontist,

  /// Dental sub-specialty: Pediatric Dentist (children's dentistry).
  pediatricDentist,

  /// Dental sub-specialty: Oral & Maxillofacial Pathologist (biopsies,
  /// histopathology).
  oralPathologist,

  /// Dental sub-specialty: Oral Medicine Specialist (mucosal disease).
  oralMedicine,

  /// Dental sub-specialty: Dental Anesthesiologist (sedation).
  dentalAnesthesiologist,

  /// Dental sub-specialty: Prosthodontist (crowns, bridges, dentures).
  prosthodontist,

  /// Dental sub-specialty: Orthodontist (braces, aligners).
  orthodontist,

  /// Dental sub-specialty: Public Health Dentist (camps, population
  /// health).
  publicHealthDentist,

  /// Dental sub-specialty: Oral & Maxillofacial Surgeon (extractions,
  /// implants, surgery).
  oralSurgeon,
}

/// Metadata, theming, and demo presets for each specialty.
class DoctorSpecialty {
  const DoctorSpecialty._({
    required this.type,
    required this.label,
    required this.shortLabel,
    required this.tagline,
    required this.icon,
    required this.accentColor,
    required this.gradientColors,
    required this.demoEmail,
    required this.demoPassword,
    required this.quickActions,
    this.parent,
  });

  final DoctorSpecialtyType type;

  /// Human-readable label, e.g. "Cardiologist".
  final String label;

  /// Short label for pills / badges, e.g. "Cardio".
  final String shortLabel;

  /// Hero tagline shown on the auth screen.
  final String tagline;

  final IconData icon;

  /// Primary accent color for this specialty.
  final Color accentColor;

  /// Gradient colors for background ambient theming.
  final List<Color> gradientColors;

  /// Demo account credentials for quick testing.
  final String demoEmail;
  final String demoPassword;

  /// Specialty-specific quick action labels.
  final List<String> quickActions;

  /// The specialty this one sits under (Oral & Maxillofacial Radiologist
  /// sits under Dentist). Null for a top-level specialty.
  final DoctorSpecialtyType? parent;

  /// The top-level specialty: this one, or the one it sits under.
  DoctorSpecialtyType get rootType => parent ?? type;

  /// Whether picking [other] in a top-level picker selects this one.
  bool isUnder(DoctorSpecialtyType other) => rootType == other;

  // ─────────────────────────── Registry ───────────────────────────

  static const List<DoctorSpecialty> all = [
    _generalPhysician,
    _physiotherapist,
    _homeopath,
    _cardiologist,
    _pediatrician,
    _dentist,
    _dermatologist,
    _orthopedic,
    _gynecologist,
    _psychiatrist,
  ];

  static const _generalPhysician = DoctorSpecialty._(
    type: DoctorSpecialtyType.generalPhysician,
    label: 'General Physician',
    shortLabel: 'General Physician',
    tagline: 'Comprehensive Primary Care, Diagnosis & Internal Medicine',
    icon: Icons.medical_services_rounded,
    accentColor: Color(0xFF2563EB),
    gradientColors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE), Color(0xFFE0F2FE)],
    demoEmail: 'doctor@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Quick Vitals', 'Prescription Pad', 'Lab Order', 'Consultation'],
  );

  static const _cardiologist = DoctorSpecialty._(
    type: DoctorSpecialtyType.cardiologist,
    label: 'Cardiologist',
    shortLabel: 'Cardio',
    tagline: 'Cardiovascular Care & Monitoring',
    icon: Icons.favorite_rounded,
    accentColor: Color(0xFFDC2626),
    gradientColors: [Color(0xFFFEE2E2), Color(0xFFFECACA), Color(0xFFFDE8E8)],
    demoEmail: 'cardio@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['ECG Log', 'BP Trend', 'Echo Report', 'Lipid Panel'],
  );

  static const _pediatrician = DoctorSpecialty._(
    type: DoctorSpecialtyType.pediatrician,
    label: 'Pediatrician',
    shortLabel: 'Pedia',
    tagline: 'Child Health & Developmental Care',
    icon: Icons.child_care_rounded,
    accentColor: Color(0xFF8B5CF6),
    gradientColors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE), Color(0xFFF3E8FF)],
    demoEmail: 'pedia@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Growth Chart', 'Immunization', 'Milestones', 'Parent Alert'],
  );

  static const _dentist = DoctorSpecialty._(
    type: DoctorSpecialtyType.dentist,
    label: 'Dentist',
    shortLabel: 'Dental',
    tagline: 'Dental Clinic & Oral Health Suite',
    icon: Icons.sentiment_satisfied_alt_rounded,
    accentColor: Color(0xFF0D9488),
    gradientColors: [Color(0xFFCCFBF1), Color(0xFF99F6E4), Color(0xFFD1FAE5)],
    demoEmail: 'dental@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Tooth Chart', 'Procedure Log', 'Sterilization', 'Dental Inv.'],
  );

  static const _dermatologist = DoctorSpecialty._(
    type: DoctorSpecialtyType.dermatologist,
    label: 'Dermatologist',
    shortLabel: 'Derm',
    tagline: 'Skin Health & Cosmetic Care',
    icon: Icons.face_retouching_natural_rounded,
    accentColor: Color(0xFFEA580C),
    gradientColors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5), Color(0xFFFEF3C7)],
    demoEmail: 'derm@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Lesion Photo', 'Biopsy Tracker', 'Skin Typing', 'Cosmetic'],
  );

  static const _orthopedic = DoctorSpecialty._(
    type: DoctorSpecialtyType.orthopedic,
    label: 'Orthopedic',
    shortLabel: 'Ortho',
    tagline: 'Musculoskeletal & Joint Care',
    icon: Icons.accessibility_new_rounded,
    accentColor: Color(0xFF0284C7),
    gradientColors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD), Color(0xFFCFFAFE)],
    demoEmail: 'ortho@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Joint Score', 'X-Ray / MRI', 'Physio Order', 'Rehab Log'],
  );

  static const _gynecologist = DoctorSpecialty._(
    type: DoctorSpecialtyType.gynecologist,
    label: 'Gynecologist',
    shortLabel: 'Gynec',
    tagline: 'Women\'s Health & Obstetric Care',
    icon: Icons.pregnant_woman_rounded,
    accentColor: Color(0xFFDB2777),
    gradientColors: [Color(0xFFFCE7F3), Color(0xFFFBCFE8), Color(0xFFFFF1F2)],
    demoEmail: 'gynec@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['EDD Calc', 'Trimester Log', 'ANC Visit', 'Ultrasound'],
  );

  static const _psychiatrist = DoctorSpecialty._(
    type: DoctorSpecialtyType.psychiatrist,
    label: 'Psychiatrist',
    shortLabel: 'Psych',
    tagline: 'Mental Health & Neurological Care',
    icon: Icons.psychology_rounded,
    accentColor: Color(0xFF4F46E5),
    gradientColors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE), Color(0xFFEDE9FE)],
    demoEmail: 'psych@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['PHQ-9 / GAD-7', 'Session Log', 'Mood Chart', 'Rx Monitor'],
  );

  static const _physiotherapist = DoctorSpecialty._(
    type: DoctorSpecialtyType.physiotherapy,
    label: 'Physiotherapist',
    shortLabel: 'Physiotherapy',
    tagline: 'Physical Rehabilitation, Mobility & Musculoskeletal Care',
    icon: Icons.accessibility_rounded,
    accentColor: Color(0xFF0D9488),
    gradientColors: [Color(0xFFCCFBF1), Color(0xFF99F6E4), Color(0xFFE6FFFA)],
    demoEmail: 'physio@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Rehab Session', 'ROM Evaluation', 'Exercise Rx', 'Package Balance'],
  );

  static const _homeopath = DoctorSpecialty._(
    type: DoctorSpecialtyType.homeopathy,
    label: 'Homeopath',
    shortLabel: 'Homeopathy',
    tagline: 'Holistic Homeopathic Case Taking & Constitutional Care',
    icon: Icons.spa_rounded,
    accentColor: Color(0xFF059669),
    gradientColors: [Color(0xFFD1FAE5), Color(0xFFA7F3D0), Color(0xFFECFDF5)],
    demoEmail: 'homeo@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Case Sheet', 'Repertorize', 'Remedy Rx', 'SRP Symptoms'],
  );

  /// Sub-specialties under Dentist, picked after Dentist.
  static const List<DoctorSpecialty> dentalSubspecialties = [
    _oralRadiologist,
    _periodontist,
    _endodontist,
    _pediatricDentist,
    _oralPathologist,
    _oralMedicine,
    _dentalAnesthesiologist,
    _prosthodontist,
    _orthodontist,
    _publicHealthDentist,
    _oralSurgeon,
  ];

  /// Every specialty, sub-specialties included (for lookups).
  static const List<DoctorSpecialty> everything = [
    ...all,
    ...dentalSubspecialties,
  ];

  /// Sub-specialties under [type], empty for most.
  static List<DoctorSpecialty> subspecialtiesOf(DoctorSpecialtyType type) =>
      type == DoctorSpecialtyType.dentist ? dentalSubspecialties : const [];

  /// The specialty for [type], sub-specialties included.
  static DoctorSpecialty ofType(DoctorSpecialtyType type) =>
      everything.firstWhere((s) => s.type == type,
          orElse: () => _generalPhysician);

  static const _oralRadiologist = DoctorSpecialty._(
    type: DoctorSpecialtyType.oralRadiologist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Oral & Maxillofacial Radiologist',
    shortLabel: 'OMR',
    tagline: 'CBCT, X-ray Reading & Radiology Reports',
    icon: Icons.view_in_ar_rounded,
    accentColor: Color(0xFF0E7490),
    gradientColors: [Color(0xFFCFFAFE), Color(0xFFA5F3FC), Color(0xFFE0F2FE)],
    demoEmail: 'omr@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Worklist', 'Import scans', 'Reports', 'Referrers'],
  );

  static const _periodontist = DoctorSpecialty._(
    type: DoctorSpecialtyType.periodontist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Periodontist',
    shortLabel: 'Perio',
    tagline: 'Gum Health, Scaling & Periodontal Surgery',
    icon: Icons.healing_rounded,
    accentColor: Color(0xFF15803D),
    gradientColors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0), Color(0xFFD1FAE5)],
    demoEmail: 'perio@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Perio Chart', 'Pocket Depths', 'SRP Plan', 'Recall'],
  );

  static const _endodontist = DoctorSpecialty._(
    type: DoctorSpecialtyType.endodontist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Endodontist',
    shortLabel: 'Endo',
    tagline: 'Root Canal Therapy & Pulp Diagnosis',
    icon: Icons.linear_scale_rounded,
    accentColor: Color(0xFFB91C1C),
    gradientColors: [Color(0xFFFEE2E2), Color(0xFFFECACA), Color(0xFFFFE4E6)],
    demoEmail: 'endo@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Root Canal', 'Vitality Test', 'Obturation', 'Referral'],
  );

  static const _pediatricDentist = DoctorSpecialty._(
    type: DoctorSpecialtyType.pediatricDentist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Pediatric Dentist',
    shortLabel: 'Pedo',
    tagline: "Child-Friendly Dental Care & Behaviour Guidance",
    icon: Icons.emoji_emotions_rounded,
    accentColor: Color(0xFFF59E0B),
    gradientColors: [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFFEDD5)],
    demoEmail: 'pedo@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Behaviour Mgmt', 'Fluoride', 'Sealants', 'Growth Chart'],
  );

  static const _oralPathologist = DoctorSpecialty._(
    type: DoctorSpecialtyType.oralPathologist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Oral & Maxillofacial Pathologist',
    shortLabel: 'OMP',
    tagline: 'Oral Biopsy, Histopathology & Lesion Diagnosis',
    icon: Icons.biotech_rounded,
    accentColor: Color(0xFF7C3AED),
    gradientColors: [Color(0xFFEDE9FE), Color(0xFFDDD6FE), Color(0xFFF3E8FF)],
    demoEmail: 'omp@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Biopsy Log', 'Histopath', 'Lesion Photo', 'Report'],
  );

  static const _oralMedicine = DoctorSpecialty._(
    type: DoctorSpecialtyType.oralMedicine,
    parent: DoctorSpecialtyType.dentist,
    label: 'Oral Medicine Specialist',
    shortLabel: 'OralMed',
    tagline: 'Oral Mucosal Disease & Diagnostic Medicine',
    icon: Icons.medical_information_rounded,
    accentColor: Color(0xFF0891B2),
    gradientColors: [Color(0xFFCFFAFE), Color(0xFFA5F3FC), Color(0xFFE0F2FE)],
    demoEmail: 'oralmed@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Lesion Exam', 'Mucosal Chart', 'Biopsy Referral', 'Forms'],
  );

  static const _dentalAnesthesiologist = DoctorSpecialty._(
    type: DoctorSpecialtyType.dentalAnesthesiologist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Dental Anesthesiologist',
    shortLabel: 'Anaesth',
    tagline: 'Sedation, Anaesthesia & Perioperative Care',
    icon: Icons.vaccines_rounded,
    accentColor: Color(0xFF6366F1),
    gradientColors: [Color(0xFFE0E7FF), Color(0xFFC7D2FE), Color(0xFFEDE9FE)],
    demoEmail: 'anaesth@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Sedation Plan', 'Vitals Log', 'Consent', 'Recovery'],
  );

  static const _prosthodontist = DoctorSpecialty._(
    type: DoctorSpecialtyType.prosthodontist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Prosthodontist',
    shortLabel: 'Prostho',
    tagline: 'Crowns, Bridges, Dentures & Implant Prosthetics',
    icon: Icons.precision_manufacturing_rounded,
    accentColor: Color(0xFFA16207),
    gradientColors: [Color(0xFFFEF9C3), Color(0xFFFEF08A), Color(0xFFFEF3C7)],
    demoEmail: 'prostho@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Impression', 'Lab Order', 'Shade Match', 'Try-in'],
  );

  static const _orthodontist = DoctorSpecialty._(
    type: DoctorSpecialtyType.orthodontist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Orthodontist',
    shortLabel: 'Ortho',
    tagline: 'Braces, Aligners & Bite Correction',
    icon: Icons.align_horizontal_center_rounded,
    accentColor: Color(0xFF16A34A),
    gradientColors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0), Color(0xFFECFCCB)],
    demoEmail: 'orthodontist@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Cephalometric', 'Bracket Chart', 'Wire Change', 'Retainer'],
  );

  static const _publicHealthDentist = DoctorSpecialty._(
    type: DoctorSpecialtyType.publicHealthDentist,
    parent: DoctorSpecialtyType.dentist,
    label: 'Public Health Dentist',
    shortLabel: 'PHD',
    tagline: 'Community Dental Camps & Population Health',
    icon: Icons.location_city_rounded,
    accentColor: Color(0xFF1D4ED8),
    gradientColors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE), Color(0xFFE0F2FE)],
    demoEmail: 'phd@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Camp Log', 'Screening', 'Survey', 'Outreach'],
  );

  static const _oralSurgeon = DoctorSpecialty._(
    type: DoctorSpecialtyType.oralSurgeon,
    parent: DoctorSpecialtyType.dentist,
    label: 'Oral & Maxillofacial Surgeon',
    shortLabel: 'OMFS',
    tagline: 'Extractions, Implants & Maxillofacial Surgery',
    icon: Icons.content_cut_rounded,
    accentColor: Color(0xFF7F1D1D),
    gradientColors: [Color(0xFFFFE4E6), Color(0xFFFECDD3), Color(0xFFFEE2E2)],
    demoEmail: 'omfs@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Surgery Log', 'Implant Plan', 'Consent', 'Post-op'],
  );

  // ─────────────────────────── Helpers ───────────────────────────

  /// Resolve a specialty from a raw string stored in Firestore.
  /// Falls back to General Physician if nothing matches.
  static DoctorSpecialty fromString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return _generalPhysician;
    final lower = raw.trim().toLowerCase();

    for (final spec in everything) {
      if (lower == spec.label.toLowerCase() ||
          lower == spec.shortLabel.toLowerCase() ||
          lower == spec.type.name.toLowerCase()) {
        return spec;
      }
    }

    // Explicit keyword matching for each distinct clinical discipline:
    if (lower.contains('homeo') || lower.contains('bhms')) {
      return _homeopath;
    }
    if (lower.contains('physio') ||
        lower.contains('physical ther') ||
        lower.contains('rehab') ||
        lower.contains('kinesio') ||
        lower.contains('bpt') ||
        lower.contains('mpt')) {
      return _physiotherapist;
    }
    if (lower.contains('physician') ||
        lower.contains('general med') ||
        lower.contains('internal med') ||
        lower.contains('family doc') ||
        lower.contains('primary care') ||
        lower.contains('general practice') ||
        lower.contains('mbbs')) {
      return _generalPhysician;
    }
    if (lower.contains('cardio') || lower.contains('heart')) {
      return _cardiologist;
    }
    if (lower.contains('pedia') || lower.contains('child')) {
      return _pediatrician;
    }
    if (lower.contains('radiolog') || lower.contains('maxillofacial')) {
      return _oralRadiologist;
    }
    if (lower.contains('periodont')) return _periodontist;
    if (lower.contains('endodont')) return _endodontist;
    if (lower.contains('pedo') || lower.contains('pediatric dent')) {
      return _pediatricDentist;
    }
    if (lower.contains('oral patholog') || lower.contains('maxillofacial patholog')) {
      return _oralPathologist;
    }
    if (lower.contains('oral med')) return _oralMedicine;
    if (lower.contains('dental anesth') || lower.contains('dental anaesth')) {
      return _dentalAnesthesiologist;
    }
    if (lower.contains('prosthodont')) return _prosthodontist;
    if (lower.contains('orthodont')) return _orthodontist;
    if (lower.contains('public health dent')) return _publicHealthDentist;
    if (lower.contains('oral surg') || lower.contains('maxillofacial surg')) {
      return _oralSurgeon;
    }
    if (lower.contains('dent') || lower.contains('oral')) return _dentist;
    if (lower.contains('derm') || lower.contains('skin')) {
      return _dermatologist;
    }
    if (lower.contains('ortho') || lower.contains('bone') || lower.contains('joint')) {
      return _orthopedic;
    }
    if (lower.contains('gynec') || lower.contains('obstet')) {
      return _gynecologist;
    }
    if (lower.contains('psych') || lower.contains('neuro') || lower.contains('mental')) {
      return _psychiatrist;
    }

    return _generalPhysician;
  }

  /// The default specialty used throughout the app.
  static DoctorSpecialty get defaultSpecialty => _generalPhysician;
}
