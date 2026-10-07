import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/subscription/data/doctor_subscription_service.dart';

/// Who is signed in, as the sidebar and greeting need it. Every field is
/// null when the profile doesn't have it — never a stand-in value.
class DoctorIdentity {
  const DoctorIdentity({
    this.fullName,
    this.clinicName,
    this.specialty,
    this.isDoctor = true,
  });

  /// "Dr. Ananya Deshpande".
  final String? fullName;
  final String? clinicName;
  final String? specialty;

  /// Staff are greeted by first name, not "Dr.".
  final bool isDoctor;

  /// "Dr. Deshpande" for the greeting.
  String? get greetingName {
    final name = fullName?.trim();
    if (name == null || name.isEmpty) return null;
    final parts = name.split(RegExp(r'\s+'));
    if (!isDoctor) return parts.first;
    final hasTitle = parts.first.toLowerCase().startsWith('dr');
    final rest = hasTitle ? parts.skip(1).toList() : parts;
    if (rest.isEmpty) return name;
    return 'Dr. ${rest.last}';
  }
}

/// The doctor's `users/{uid}` profile document.
final doctorProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(authStateProvider).value;
  return DoctorProfileHelper.watchDoctorProfile(user);
});

final doctorIdentityProvider = Provider<DoctorIdentity>((ref) {
  final user = ref.watch(authStateProvider).value;
  final profile = ref.watch(doctorProfileProvider).value;
  final access = ref.watch(clinicAccessProvider).value;
  final own = DoctorIdentity(
    fullName: DoctorProfileHelper.tryFormatDoctorName(user, profile),
    clinicName: DoctorProfileHelper.tryFormatClinicName(user, profile),
    specialty: DoctorProfileHelper.formatSpecialty(profile, user),
  );
  if (access == null || access.isOwner) return own;
  // Someone working in another person's clinic: that clinic's name, and
  // their role for staff.
  final clinicName = ref.watch(activeClinicProvider).value?.name;
  final isDoctor = access.kind == MemberKind.doctor;
  return DoctorIdentity(
    fullName: ClinicSession.instance.member?.name.trim().isNotEmpty == true
        ? ClinicSession.instance.member!.name
        : own.fullName,
    clinicName: clinicName == null || clinicName.isEmpty
        ? own.clinicName
        : clinicName,
    specialty: isDoctor ? own.specialty : access.roleName,
    isDoctor: isDoctor,
  );
});

/// Plan and days remaining for the sidebar footer.
final subscriptionInfoProvider = StreamProvider<DoctorSubscriptionInfo>((ref) {
  ref.watch(authStateProvider);
  return DoctorSubscriptionService().watchSubscriptionInfo();
});
