import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';

/// In-memory trial / dev session manager that guarantees instantaneous,
/// rate-limit-proof login and on-the-fly specialty switching without Firebase network blockers.
class DemoSessionService {
  DemoSessionService._();

  static bool _isDemoMode = false;
  static bool get isDemoMode => _isDemoMode;

  static bool _isSuperAdminMode = false;
  static bool get isSuperAdminMode => _isSuperAdminMode;

  static DoctorSpecialty _activeSpecialty = DoctorSpecialty.defaultSpecialty;
  static DoctorSpecialty get activeSpecialty => _activeSpecialty;

  static final ValueNotifier<bool> sessionStateNotifier = ValueNotifier<bool>(
    false,
  );

  static final ValueNotifier<int> sessionRevisionNotifier = ValueNotifier<int>(0);

  static final ValueNotifier<DoctorSpecialty> specialtyNotifier =
      ValueNotifier<DoctorSpecialty>(DoctorSpecialty.defaultSpecialty);

  static final StreamController<Map<String, dynamic>> _profileStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get profileStream =>
      _profileStreamController.stream;

  static Map<String, dynamic> get currentMockProfile => _isSuperAdminMode
      ? {
          'uid': 'demo_super_admin_dev',
          'email': 'admin@crudoc.com',
          'displayName': 'Super Administrator (Dev)',
          'doctorName': 'Super Administrator',
          'specialty': 'Platform Administration',
          'specialization': 'Super Admin',
          'clinicName': 'CruDoc HQ Platform',
          'status': 'Active',
          'role': 'superAdmin',
          'isDemoAccount': true,
        }
      : {
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
      case DoctorSpecialtyType.oralRadiologist:
        return 'Dr. Meera Radiology';
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
      case DoctorSpecialtyType.periodontist:
        return 'Dr. Maya Perio';
      case DoctorSpecialtyType.endodontist:
        return 'Dr. Vikram Endo';
      case DoctorSpecialtyType.pediatricDentist:
        return 'Dr. Ananya PediaDent';
      case DoctorSpecialtyType.oralPathologist:
        return 'Dr. Kabir Patho';
      case DoctorSpecialtyType.oralMedicine:
        return 'Dr. Sunita Med';
      case DoctorSpecialtyType.dentalAnesthesiologist:
        return 'Dr. Farhan Sedation';
      case DoctorSpecialtyType.prosthodontist:
        return 'Dr. Gaurav Prosth';
      case DoctorSpecialtyType.orthodontist:
        return 'Dr. Riya Ortho';
      case DoctorSpecialtyType.publicHealthDentist:
        return 'Dr. Alok Health';
      case DoctorSpecialtyType.oralSurgeon:
        return 'Dr. Devendra Surgeon';
    }
  }

  /// Starts an active offline/online trial demo session for doctor.
  static void startDemoSession([DoctorSpecialty? specialty]) {
    _isDemoMode = true;
    _isSuperAdminMode = false;
    _activeSpecialty = specialty ?? DoctorSpecialty.defaultSpecialty;
    sessionStateNotifier.value = true;
    sessionRevisionNotifier.value++;
    specialtyNotifier.value = _activeSpecialty;
    _profileStreamController.add(currentMockProfile);
  }

  /// Starts an active offline/online trial demo session for Super Admin.
  static void startSuperAdminDemoSession() {
    _isDemoMode = true;
    _isSuperAdminMode = true;
    sessionStateNotifier.value = true;
    sessionRevisionNotifier.value++;
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
    _isSuperAdminMode = false;
    sessionStateNotifier.value = false;
    sessionRevisionNotifier.value++;
    _activeSpecialty = DoctorSpecialty.defaultSpecialty;
    specialtyNotifier.value = _activeSpecialty;
  }
}
