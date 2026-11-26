import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_page.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The patient the sidebar's Physio page shows. Kept while you visit other
/// pages and come back.
final physioPatientIdProvider = StateProvider<String?>((ref) => null);

/// A patient's Physio workspace inside the shell (the sidebar stays),
/// opened from a patient's header or row button. The search on top switches
/// patient. It has no empty page: with no patient picked it goes back to
/// Patients.
class PhysioPage extends ConsumerWidget {
  const PhysioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600
        ? CruSpace.mainPaddingPhone
        : width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;
    final now = ref.watch(apptsNowProvider);
    final day = ref.watch(apptDayItemsProvider(ApptsBuilder.dateOnly(now)));
    final items = day.value ?? const <ApptItem>[];
    final patientsAsync = ref.watch(patientsStreamProvider);
    final patientsLoaded = patientsAsync.hasValue;
    final patients = patientsAsync.value ?? const [];
    final chosen = ref.watch(physioPatientIdProvider);

    Patient? patient;
    if (chosen != null) {
      for (final p in patients) {
        if (p.id == chosen) {
          patient = p;
          break;
        }
      }
    }

    final picker = PatientSearch(
      items: items,
      patients: patients,
      current: patient,
      semanticPrefix: 'Physio',
      onPick: (p) => ref.read(physioPatientIdProvider.notifier).state = p.id,
    );

    if (patient == null) {
      if (chosen == null || patientsLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(shellNavigatorProvider)?.call(DesktopTab.patients);
        });
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: padding,
      child: PhysioScreen(
        key: ValueKey(patient.id),
        patient: patient,
        embedded: true,
        picker: picker,
      ),
    );
  }
}
