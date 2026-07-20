import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/widgets/last_patient.dart';
import 'package:doctor_management_app/features/patients/widgets/upcoming_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_details.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';

class PatientRecords extends StatelessWidget {
  const PatientRecords({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Patients Record',
                style: AppColors.pageHeading,
              ),
              const SizedBox(height: 8),
              const _SearchBar(),
              const SizedBox(height: 16),
              const LastPatientsCard(),
              const SizedBox(height: 16),
              const UpcomingPatientCard(),
              // ------ "All Patients" section (same rhythm as other screens) ------
              const SizedBox(height: 28),                         // more breathing room above heading
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'All Patients',
                    style: AppColors.pageHeading.copyWith(
                      fontSize: 18,                               // smaller, consistent
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AddPatientPage()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.chartBarLight,           // accent-blue fill (matches + buttons)
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add,
                              color: Colors.white, size: 18),     // white icon
                          SizedBox(width: 4),
                          Text(
                            'Add',
                            style: TextStyle(
                              color: Colors.white,                // white text
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),                           // tighter gap to list below
              const Expanded(
                child: _PatientsList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- SEARCH BAR ----------
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, color: AppColors.silver, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              style: AppColors.bodyMedium,
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).state = value;
                setState(() {});
              },
              decoration: const InputDecoration(
                hintText: 'Search by name, phone, diagnosis...',
                hintStyle: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.silver,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
                setState(() {});
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ---------- PATIENTS LIST (real data, reactive) ----------
class _PatientsList extends ConsumerWidget {
  const _PatientsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(filteredPatientsProvider);
    final searchQuery = ref.watch(searchQueryProvider);

    return patientsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text(
          'Error loading patients: $error',
          style: AppColors.bodyMedium,
        ),
      ),
      data: (patients) {
        if (patients.isEmpty) {
          final message = searchQuery.isEmpty
              ? 'No patients yet — tap Add to create one'
              : 'No matches';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                message,
                style: AppColors.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemExtent: 82.0,
          itemCount: patients.length,
          itemBuilder: (context, index) =>
              _PatientTile(patient: patients[index]),
        );
      },
    );
  }
}

// ---------- PATIENT TILE (real Patient model) ----------
class _PatientTile extends StatelessWidget {
  final Patient patient;
  const _PatientTile({required this.patient});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PatientDetailsPage(patient: patient),
              ),
            );
          },
          child: Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const SizedBox(width: 5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        patient.fullName,
                        style: AppColors.bodyLarge.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${patient.gender.isNotEmpty ? patient.gender[0] : ''}, ${patient.age}  •  ${_formatRelativeTime(patient.updatedAt)}',
                        style: AppColors.bodySmall.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.silver, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- HELPER: relative time formatting ----------
String _formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    final mins = difference.inMinutes;
    return '$mins ${mins == 1 ? 'minute' : 'minutes'} ago';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  } else if (difference.inDays < 30) {
    final days = difference.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  } else if (difference.inDays < 365) {
    final months = (difference.inDays / 30).floor();
    return '$months ${months == 1 ? 'month' : 'months'} ago';
  } else {
    final years = (difference.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }
}