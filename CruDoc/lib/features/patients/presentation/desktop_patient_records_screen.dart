import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_records.dart';

/// Desktop version of the Patient Records tab.
///
/// For now this just reuses the exact same mobile [PatientRecords] screen
/// and centers it in a max-width column so it doesn't stretch edge-to-edge
/// on a wide window. Nothing about the mobile screen changes.
///
/// Intentionally a placeholder — replace with a real desktop layout
/// (e.g. list + detail split view) whenever you're ready.
class DesktopPatientRecordsScreen extends StatelessWidget {
  const DesktopPatientRecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: PatientRecords(),
      ),
    );
  }
}