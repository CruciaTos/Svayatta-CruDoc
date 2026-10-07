import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/dental/dental_features.dart';

/// In-memory trial / dev session manager that guarantees instantaneous,
/// rate-limit-proof login and on-the-fly specialty switching without Firebase network blockers.
class DemoSessionService {
  DemoSessionService._();

  static bool _isDemoMode = false;
  static bool get isDemoMode => _isDemoMode;

  static DoctorSpecialty _activeSpecialty = DoctorSpecialty.defaultSpecialty;
  static DoctorSpecialty get activeSpecialty => _activeSpecialty;

  static final ValueNotifier<bool> sessionStateNotifier = ValueNotifier<bool>(
    false,
  );

  static final ValueNotifier<int> sessionRevisionNotifier = ValueNotifier<int>(
    0,
  );

  static final ValueNotifier<DoctorSpecialty> specialtyNotifier =
      ValueNotifier<DoctorSpecialty>(DoctorSpecialty.defaultSpecialty);

  static final StreamController<Map<String, dynamic>> _profileStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get profileStream =>
      _profileStreamController.stream;

  static Set<DentalFeature>? _demoDentalFeatures;
  static void setDentalFeatures(Set<DentalFeature> features) {
    _demoDentalFeatures = features;
    _profileStreamController.add(currentMockProfile);
  }

  static Map<String, dynamic> get currentMockProfile => {
    'uid': 'demo_doctor_dev',
    'email': _activeSpecialty.demoEmail,
    'displayName': _getDemoDoctorName(_activeSpecialty),
    'doctorName': _getDemoDoctorName(_activeSpecialty),
    'specialty': _activeSpecialty.label,
    'specialization': _activeSpecialty.label,
    'clinicName': 'CruDoc ${_activeSpecialty.shortLabel} Care Clinic',
    'status': 'Active',
    'role': 'doctor',
    'isDemoAccount': true,
    if (_activeSpecialty.type == DoctorSpecialtyType.dentist)
      'dentalFeatures': _demoDentalFeatures != null
          ? [for (final f in _demoDentalFeatures!) f.key]
          : [for (final f in DentalFeature.values) f.key],
  };

  static String _getDemoDoctorName(DoctorSpecialty specialty) {
    switch (specialty.type) {
      case DoctorSpecialtyType.dentist:
        return 'Dr. Aryan Dental';
      case DoctorSpecialtyType.homeopathy:
        return 'Dr. Vinit Homeo';
      case DoctorSpecialtyType.cardiologist:
        return 'Dr. Sarah Heart';
      case DoctorSpecialtyType.pediatrician:
        return 'Dr. Emily Kids';
      case DoctorSpecialtyType.dermatologist:
        return 'Dr. Maya Derma';
      case DoctorSpecialtyType.orthopedic:
        return 'Dr. Rajesh Bone';
      case DoctorSpecialtyType.gynecologist:
        return 'Dr. Priya WomenCare';
      case DoctorSpecialtyType.psychiatrist:
        return 'Dr. Arjun Mind';
      case DoctorSpecialtyType.physiotherapy:
        return 'Dr. Rohit Rehab';
      case DoctorSpecialtyType.generalPhysician:
        return 'Dr. Vinit Parab';
    }
  }

  /// Starts an active offline/online trial demo session for doctor.
  static void startDemoSession([DoctorSpecialty? specialty]) {
    _isDemoMode = true;
    _activeSpecialty = specialty ?? DoctorSpecialty.defaultSpecialty;
    sessionStateNotifier.value = true;
    sessionRevisionNotifier.value++;
    specialtyNotifier.value = _activeSpecialty;
    _profileStreamController.add(currentMockProfile);
  }

  /// Switches the active specialty in trial demo mode instantly.
  static void setSpecialty(DoctorSpecialty specialty) {
    _activeSpecialty = specialty;
    _demoDentalFeatures = null;
    specialtyNotifier.value = specialty;
    _profileStreamController.add(currentMockProfile);
  }

  /// Ends the trial demo session and resets state.
  static void endDemoSession() {
    _isDemoMode = false;
    sessionStateNotifier.value = false;
    sessionRevisionNotifier.value++;
    _activeSpecialty = DoctorSpecialty.defaultSpecialty;
    _demoDentalFeatures = null;
    specialtyNotifier.value = _activeSpecialty;
  }
}
