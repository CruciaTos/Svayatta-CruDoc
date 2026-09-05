import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';

/// In-memory trial / dev session manager that guarantees instantaneous,
/// rate-limit-proof login and on-the-fly specialty switching without Firebase network blockers.
class DemoSessionService {
  DemoSessionService._();

  static bool _isDemoMode = false;
  static bool get isDemoMode => _isDemoMode;

  static DoctorSpecialty _activeSpecialty = DoctorSpecialty.defaultSpecialty;
  static DoctorSpecialty get activeSpecialty => _activeSpecialty;

  static final ValueNotifier<bool> sessionStateNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<DoctorSpecialty> specialtyNotifier =
      ValueNotifier<DoctorSpecialty>(DoctorSpecialty.defaultSpecialty);

  static final StreamController<Map<String, dynamic>> _profileStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get profileStream =>
      _profileStreamController.stream;

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

  /// Starts an active offline/online trial demo session.
  static void startDemoSession([DoctorSpecialty? specialty]) {
    _isDemoMode = true;
    _activeSpecialty = specialty ?? DoctorSpecialty.defaultSpecialty;
    sessionStateNotifier.value = true;
    specialtyNotifier.value = _activeSpecialty;
    _profileStreamController.add(currentMockProfile);
  }

  /// Switches the active specialty in trial demo mode instantly.
  static void setSpecialty(DoctorSpecialty specialty) {
    _activeSpecialty = specialty;
    specialtyNotifier.value = specialty;
    _profileStreamController.add(currentMockProfile);
  }

  /// Ends the trial demo session and resets state.
  static void endDemoSession() {
    _isDemoMode = false;
    sessionStateNotifier.value = false;
    _activeSpecialty = DoctorSpecialty.defaultSpecialty;
    specialtyNotifier.value = _activeSpecialty;
  }
}
