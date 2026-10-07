import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';

/// What a dentist uses CruDoc for. Replaces the dental sub-specialty logins:
/// a dentist turns on any mix. Stored per person as
/// `users/{uid}.dentalFeatures` (the [key]s).
enum DentalFeature {
  chairside(
    'chairside',
    'General dentistry',
    'Tooth chart, treatment plans, recalls, referrals, sterilization, procedures',
  ),
  radiology(
    'radiology',
    'Radiology',
    'Scan worklist, viewer, reports and referrers',
  ),
  perio('perio', 'Periodontics', 'Perio charting and maintenance'),
  endo('endo', 'Endodontics', 'Root canal cases'),
  pedo('pedo', 'Pediatric dentistry', "Children's care"),
  ortho('ortho', 'Orthodontics', 'Braces and aligner cases'),
  prostho(
    'prostho',
    'Prosthodontics',
    'Crowns, bridges, dentures and lab cases',
  ),
  surgery('surgery', 'Oral surgery and implants', 'Surgeries and implants'),
  pathology('pathology', 'Oral pathology', 'Biopsies'),
  oralMedicine('oral_medicine', 'Oral medicine', 'Lesions and forms'),
  sedation(
    'sedation',
    'Sedation and emergencies',
    'Sedation cases and emergency protocols',
  ),
  publicHealth('public_health', 'Public health', 'Camps and population health');

  const DentalFeature(this.key, this.label, this.detail);
  final String key;
  final String label;
  final String detail;

  static const Set<DentalFeature> defaults = {chairside, radiology};

  static DentalFeature? fromKey(String key) {
    for (final f in values) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Parses a stored list; unknown keys dropped. Null when [raw] isn't a list.
  static Set<DentalFeature>? parse(Object? raw) {
    if (raw is! Iterable) return null;
    final result = <DentalFeature>{};
    for (final item in raw) {
      if (item is String) {
        final f = fromKey(item);
        if (f != null) result.add(f);
      }
    }
    return result;
  }

  /// Features for a profile without `dentalFeatures`: the old sub-specialty
  /// table in the handoff, else [defaults].
  static Set<DentalFeature> fromLegacySpecialty(String? rawSpecialty) {
    if (rawSpecialty == null) return defaults;
    final trimmed = rawSpecialty.trim().toLowerCase();
    if (trimmed.isEmpty) return defaults;

    final legacyFeature = legacyDentalSpecialties[trimmed];
    if (legacyFeature == null) return defaults;
    if (legacyFeature == DentalFeature.radiology) {
      return {DentalFeature.radiology};
    }
    return {DentalFeature.chairside, DentalFeature.radiology, legacyFeature};
  }

  /// The feature a DesktopTab belongs to (Design A table), or null for tabs
  /// that aren't dental.
  static DentalFeature? forTab(int tab) => switch (tab) {
    DesktopTab.treatmentPlans ||
    DesktopTab.recalls ||
    DesktopTab.dentalReferrals ||
    DesktopTab.sterilization ||
    DesktopTab.procedures => chairside,
    DesktopTab.worklist ||
    DesktopTab.reports ||
    DesktopTab.referrers => radiology,
    DesktopTab.perioPatients => perio,
    DesktopTab.rootCanals => endo,
    DesktopTab.pedoChildren => pedo,
    DesktopTab.orthoPatients => ortho,
    DesktopTab.labCases => prostho,
    DesktopTab.surgeries || DesktopTab.implants => surgery,
    DesktopTab.biopsies => pathology,
    DesktopTab.oralMedLesions || DesktopTab.oralMedForms => oralMedicine,
    DesktopTab.sedationCases || DesktopTab.emergency => sedation,
    DesktopTab.healthCamps || DesktopTab.population => publicHealth,
    _ => null,
  };

  /// Whether [tab] may be shown: non-dental tabs always; dental tabs only
  /// when their feature is in [on].
  static bool allowsTab(int tab, Set<DentalFeature> on) {
    final feature = forTab(tab);
    if (feature == null) return true;
    return on.contains(feature);
  }
}

/// Lookup map for the 11 old sub-specialties to their primary feature.
const Map<String, DentalFeature> legacyDentalSpecialties = {
  // Oral & Maxillofacial Radiologist
  'oral & maxillofacial radiologist': DentalFeature.radiology,
  'omr': DentalFeature.radiology,
  'oralradiologist': DentalFeature.radiology,
  'oral radiologist': DentalFeature.radiology,

  // Periodontist
  'periodontist': DentalFeature.perio,
  'perio': DentalFeature.perio,

  // Endodontist
  'endodontist': DentalFeature.endo,
  'endo': DentalFeature.endo,

  // Pediatric Dentist
  'pediatric dentist': DentalFeature.pedo,
  'pedo': DentalFeature.pedo,
  'pediatricdentist': DentalFeature.pedo,

  // Oral & Maxillofacial Pathologist
  'oral & maxillofacial pathologist': DentalFeature.pathology,
  'omp': DentalFeature.pathology,
  'oralpathologist': DentalFeature.pathology,
  'oral pathologist': DentalFeature.pathology,

  // Oral Medicine Specialist
  'oral medicine specialist': DentalFeature.oralMedicine,
  'oralmed': DentalFeature.oralMedicine,
  'oralmedicine': DentalFeature.oralMedicine,
  'oral medicine': DentalFeature.oralMedicine,

  // Dental Anesthesiologist
  'dental anesthesiologist': DentalFeature.sedation,
  'anaesth': DentalFeature.sedation,
  'dentalanesthesiologist': DentalFeature.sedation,
  'dental anaesthesiologist': DentalFeature.sedation,

  // Prosthodontist
  'prosthodontist': DentalFeature.prostho,
  'prostho': DentalFeature.prostho,

  // Orthodontist
  'orthodontist': DentalFeature.ortho,
  'ortho': DentalFeature.ortho,

  // Public Health Dentist
  'public health dentist': DentalFeature.publicHealth,
  'phd': DentalFeature.publicHealth,
  'publichealthdentist': DentalFeature.publicHealth,

  // Oral & Maxillofacial Surgeon
  'oral & maxillofacial surgeon': DentalFeature.surgery,
  'omfs': DentalFeature.surgery,
  'oralsurgeon': DentalFeature.surgery,
  'oral surgeon': DentalFeature.surgery,
};
