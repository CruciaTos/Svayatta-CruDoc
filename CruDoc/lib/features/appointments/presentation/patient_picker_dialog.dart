import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

/// Opens a patient search/picker dialog.
/// Returns the selected patient, or null if dismissed.
Future<Patient?> showPatientPickerDialog(
  BuildContext context, {
  String title = 'Select a patient',
}) async {
  return showDialog<Patient?>(
    context: context,
    builder: (context) => _PatientPickerDialog(title: title),
  );
}

class _PatientPickerDialog extends ConsumerStatefulWidget {
  final String title;

  const _PatientPickerDialog({required this.title});

  @override
  ConsumerState<_PatientPickerDialog> createState() =>
      _PatientPickerDialogState();
}

class _PatientPickerDialogState extends ConsumerState<_PatientPickerDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the filtered patients provider with the current search query
    final patientsAsync = ref.watch(filteredPatientsProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (value) {
                setState(() => _searchQuery = value);
                // Update the search query provider to filter patients
                ref.read(searchQueryProvider.notifier).state = value;
              },
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or diagnosis…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          // Patient list
          Expanded(
            child: patientsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Error loading patients: $error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ),
              ),
              data: (patients) {
                if (patients.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No patients yet. Create one to get started.'
                            : 'No patients match "$_searchQuery".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: patients.length,
                  itemBuilder: (context, index) {
                    final patient = patients[index];
                    return _PatientListItem(
                      patient: patient,
                      onTap: () =>
                          Navigator.of(context).pop<Patient>(patient),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientListItem extends StatelessWidget {
  final Patient patient;
  final VoidCallback onTap;

  const _PatientListItem({
    required this.patient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final phone = patient.phone.trim();
    final diagnosis = patient.diagnosisDisplay.trim();
    final createdDate = DateFormat('dd/MM/yyyy').format(patient.createdAt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF7C3AED),
        child: Text(
          _initials(patient.fullName),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        patient.fullName,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone.isNotEmpty)
            Text(phone, style: TextStyle(color: Colors.grey[600])),
          if (diagnosis.isNotEmpty)
            Text(
              diagnosis,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            'Added $createdDate',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
