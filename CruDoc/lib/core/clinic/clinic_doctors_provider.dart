import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Active doctors in the active clinic.
///
/// When the clinic doc doesn't exist (solo practice), yields a single
/// entry for the signed-in doctor.
final clinicDoctorsProvider = StreamProvider<List<ClinicMember>>((ref) {
  final clinic = ref.watch(activeClinicProvider).value;
  final identity = ref.watch(doctorIdentityProvider);
  final user = ref.watch(authStateProvider).value;
  final tenantId = ClinicSession.instance.tenantId ?? user?.uid;

  ClinicMember buildFallbackDoctor() {
    return ClinicMember(
      uid: user?.uid ?? tenantId ?? '',
      name: identity.fullName ?? 'Doctor',
      phone: user?.phoneNumber ?? '',
      email: user?.email ?? '',
      kind: MemberKind.doctor,
      roleId: 'admin',
      roleName: 'Owner',
      perms: ClinicPermission.values.toSet(),
      active: true,
      isOwner: true,
      specialty: identity.specialty ?? '',
      qualification: '',
      registrationNo: '',
    );
  }

  if (clinic == null || tenantId == null) {
    return Stream.value([buildFallbackDoctor()]);
  }

  return FirebaseFirestore.instance
      .collection('clinics')
      .doc(tenantId)
      .collection('members')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((snap) {
        final doctors = snap.docs
            .map((doc) => ClinicMember.fromMap(doc.id, doc.data()))
            .where((m) => m.kind == MemberKind.doctor && m.active)
            .toList();

        if (doctors.isEmpty) {
          return [buildFallbackDoctor()];
        }

        doctors.sort((a, b) {
          if (a.isOwner && !b.isOwner) return -1;
          if (!a.isOwner && b.isOwner) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        return doctors;
      });
});

/// The filter menu's "All doctors" item.
const String _kAllDoctors = '';

/// Selected doctor filter for Appointments and Queue views.
///
/// null = All doctors.
/// Doctors default to their own UID; staff default to null (All doctors).
final scheduleDoctorFilterProvider = StateProvider<String?>((ref) {
  final access = ref.watch(clinicAccessProvider).value;
  final isDoctor = access?.kind == MemberKind.doctor;
  String? currentUid;
  try {
    currentUid = FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {}
  return isDoctor ? currentUid : null;
});

/// Dropdown filter for Schedule and Queue views, shown only when
/// there is more than one doctor in the clinic.
class ScheduleDoctorFilter extends ConsumerWidget {
  const ScheduleDoctorFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctorsAsync = ref.watch(clinicDoctorsProvider);
    final doctors = doctorsAsync.value ?? const [];
    if (doctors.length <= 1) return const SizedBox.shrink();

    final selectedUid = ref.watch(scheduleDoctorFilterProvider);
    final selectedDoc = doctors.where((d) => d.uid == selectedUid).firstOrNull;
    final label = selectedDoc != null ? selectedDoc.name : 'All doctors';

    final c = context.cru;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "All doctors" is '' not null: a menu item with a null value
        // can't be picked (Flutter treats it as closing the menu).
        PopupMenuButton<String>(
          initialValue: selectedUid ?? _kAllDoctors,
          tooltip: 'Filter by doctor',
          onSelected: (uid) {
            ref.read(scheduleDoctorFilterProvider.notifier).state =
                uid == _kAllDoctors ? null : uid;
          },
          color: c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(color: c.cardBorder),
          ),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: _kAllDoctors,
              child: Text(
                'All doctors',
                style: CruType.text.tint(
                  selectedUid == null ? c.accent : c.label,
                ),
              ),
            ),
            for (final doc in doctors)
              PopupMenuItem<String>(
                value: doc.uid,
                child: Text(
                  doc.name,
                  style: CruType.text.tint(
                    selectedUid == doc.uid ? c.accent : c.label,
                  ),
                ),
              ),
          ],
          child: Container(
            height: CruSize.squareButton,
            padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CruRadius.control),
              border: Border.all(color: c.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CruIcon(CruIcons.user, size: 14, color: c.label3),
                const SizedBox(width: CruSpace.s6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    label,
                    style: CruType.chip.tint(c.label),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: CruSpace.s4),
                CruIcon(CruIcons.chevronDown, size: 14, color: c.label3),
              ],
            ),
          ),
        ),
        const SizedBox(width: CruSpace.s10),
      ],
    );
  }
}
