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

  // ─────────────────────────── Registry ───────────────────────────

  static const List<DoctorSpecialty> all = [
    _generalPhysician,
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
    shortLabel: 'General',
    tagline: 'Comprehensive Primary Care Management',
    icon: Icons.medical_services_rounded,
    accentColor: Color(0xFF2563EB),
    gradientColors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE), Color(0xFFE0F2FE)],
    demoEmail: 'doctor@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['Quick Vitals', 'Rx Generator', 'Lab Order', 'Follow-up'],
  );

  static const _cardiologist = DoctorSpecialty._(
    type: DoctorSpecialtyType.cardiologist,
    label: 'Cardiologist',
    shortLabel: 'Cardio',
    tagline: 'Cardiovascular Care & Monitoring',
    icon: Icons.favorite_rounded,
    accentColor: Color(0xFFDC2626),
    gradientColors: [Color(0xFFFEE2E2), Color(0xFFFECACA), Color(0xFFFFE4E6)],
    demoEmail: 'cardio@crudoc.com',
    demoPassword: 'demo1234',
    quickActions: ['ECG Log', 'BP Tracker', 'Lipid Panel', 'Cardiac Risk'],
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

  // ─────────────────────────── Helpers ───────────────────────────

  /// Resolve a specialty from a raw string stored in Firestore.
  /// Falls back to General Physician if nothing matches.
  static DoctorSpecialty fromString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return _generalPhysician;
    final lower = raw.trim().toLowerCase();

    for (final spec in all) {
      if (lower == spec.label.toLowerCase() ||
          lower == spec.shortLabel.toLowerCase() ||
          lower == spec.type.name.toLowerCase()) {
        return spec;
      }
    }

    // Fuzzy fallback: check if the raw string *contains* a known keyword.
    if (lower.contains('cardio') || lower.contains('heart')) {
      return _cardiologist;
    }
    if (lower.contains('pedia') || lower.contains('child')) {
      return _pediatrician;
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
