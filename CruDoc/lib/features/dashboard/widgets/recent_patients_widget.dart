import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/desktop_patient_details_screen.dart';

/// Displays the doctor's recent patients using real data from [patientsStreamProvider].
class RecentPatientsWidget extends ConsumerWidget {
  const RecentPatientsWidget({super.key});

  String _formatInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(patientsStreamProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Patients',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: () => showAddPatientSheet(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Patient'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3F51B5),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          patientsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3F51B5),
                  ),
                ),
              ),
            ),
            error: (error, stack) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Could not load patients: $error',
                style: TextStyle(color: Colors.red[400], fontSize: 13),
              ),
            ),
            data: (patients) {
              if (patients.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.people_outline, size: 36, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No patients registered yet.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Sort by createdAt descending to get most recent patients first
              final sortedPatients = List<Patient>.from(patients)
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final recentList = sortedPatients.take(5).toList();

              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 56,
                    horizontalMargin: 12,
                    columnSpacing: 24,
                    columns: const [
                      DataColumn(label: Text('Patient Info')),
                      DataColumn(label: Text('Diagnosis')),
                      DataColumn(label: Text('Age / Gender')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Joined')),
                    ],
                    rows: recentList.map((patient) {
                      final diagnosisText = patient.diagnosisDisplay.trim().isNotEmpty
                          ? patient.diagnosisDisplay
                          : 'General';
                      final genderText = patient.gender.trim().isNotEmpty
                          ? patient.gender
                          : '—';
                      final ageText = patient.age > 0 ? '${patient.age}y' : '';
                      final ageGender = [genderText, if (ageText.isNotEmpty) ageText].join(' • ');
                      final joinedDate = DateFormat('dd MMM yyyy').format(patient.createdAt);

                      return DataRow(
                        onSelectChanged: (_) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DesktopPatientDetailsScreen(patient: patient),
                            ),
                          );
                        },
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFF6366F1).withOpacity(0.15),
                                  child: Text(
                                    _formatInitials(patient.fullName),
                                    style: const TextStyle(
                                      color: Color(0xFF4F46E5),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      patient.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    if (patient.phone.trim().isNotEmpty)
                                      Text(
                                        patient.phone,
                                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3F51B5).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                diagnosisText,
                                style: const TextStyle(
                                  color: Color(0xFF3F51B5),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              ageGender,
                              style: TextStyle(color: Colors.grey[700], fontSize: 12),
                            ),
                          ),
                          DataCell(
                            _StatusBadge(
                              text: patient.isArchived ? 'Archived' : 'Active',
                              color: patient.isArchived ? Colors.grey : const Color(0xFF10B981),
                            ),
                          ),
                          DataCell(
                            Text(
                              joinedDate,
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}