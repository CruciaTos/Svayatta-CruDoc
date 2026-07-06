import 'package:flutter/material.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patient_records/widgets/last_patient.dart';
import 'package:doctor_management_app/features/patient_records/widgets/upcoming_patient.dart';
import 'package:doctor_management_app/features/patient_records/presentation/patient_details.dart';

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
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const _SearchBar(),
              const SizedBox(height: 16),
              const LastPatientsCard(),
              const SizedBox(height: 16),
              const UpcomingPatientCard(),
              const SizedBox(height: 16),
              const Text(
                'All Patients',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
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
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Row(
        children: [
          SizedBox(width: 12),
          Icon(Icons.search, color: AppColors.silver, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search patient...',
                hintStyle:
                    TextStyle(color: AppColors.textSecondary, fontSize: 14),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- PATIENTS LIST ----------
class _PatientsList extends StatelessWidget {
  const _PatientsList();

  static const List<_PatientData> _patients = [
    _PatientData(
      name: 'Emily Clark',
      age: 32,
      gender: 'Female',
      condition: 'Hypertension',
      address: '123 Oak Street, Springfield',
      contact: '+1 (555) 123-4567',
      secondContact: '+1 (555) 987-6543',
      sessionsAttended: 12,
      lastVisit: '2 hours ago',
    ),
    _PatientData(
      name: 'Michael Brown',
      age: 45,
      gender: 'Male',
      condition: 'Diabetes Type 2',
      address: '456 Maple Ave, Shelbyville',
      contact: '+1 (555) 234-5678',
      secondContact: '+1 (555) 876-5432',
      sessionsAttended: 8,
      lastVisit: '1 day ago',
    ),
    _PatientData(
      name: 'Sophia Lee',
      age: 29,
      gender: 'Female',
      condition: 'Asthma',
      address: '789 Pine Road, Capital City',
      contact: '+1 (555) 345-6789',
      secondContact: '+1 (555) 765-4321',
      sessionsAttended: 5,
      lastVisit: '3 days ago',
    ),
    _PatientData(
      name: 'James Wilson',
      age: 56,
      gender: 'Male',
      condition: 'Arthritis',
      address: '321 Elm St, Ogdenville',
      contact: '+1 (555) 456-7890',
      secondContact: '+1 (555) 654-3210',
      sessionsAttended: 20,
      lastVisit: '5 days ago',
    ),
    _PatientData(
      name: 'Olivia Martinez',
      age: 41,
      gender: 'Female',
      condition: 'Migraine',
      address: '654 Cedar Lane, North Haverbrook',
      contact: '+1 (555) 567-8901',
      secondContact: '+1 (555) 543-2109',
      sessionsAttended: 15,
      lastVisit: '1 week ago',
    ),
    _PatientData(
      name: 'Liam Johnson',
      age: 27,
      gender: 'Male',
      condition: 'Allergies',
      address: '987 Birch Blvd, Brockway',
      contact: '+1 (555) 678-9012',
      secondContact: '+1 (555) 432-1098',
      sessionsAttended: 3,
      lastVisit: '2 weeks ago',
    ),
    _PatientData(
      name: 'Ava Thompson',
      age: 38,
      gender: 'Female',
      condition: 'Thyroid Disorder',
      address: '246 Spruce Way, Springfield',
      contact: '+1 (555) 789-0123',
      secondContact: '+1 (555) 321-0987',
      sessionsAttended: 10,
      lastVisit: '3 weeks ago',
    ),
    _PatientData(
      name: 'Noah Garcia',
      age: 62,
      gender: 'Male',
      condition: 'Heart Disease',
      address: '135 Walnut Dr, Capital City',
      contact: '+1 (555) 890-1234',
      secondContact: '+1 (555) 210-9876',
      sessionsAttended: 25,
      lastVisit: '1 month ago',
    ),
    _PatientData(
      name: 'Isabella Davis',
      age: 33,
      gender: 'Female',
      condition: 'Anxiety',
      address: '864 Chestnut Ct, Ogdenville',
      contact: '+1 (555) 901-2345',
      secondContact: '+1 (555) 109-8765',
      sessionsAttended: 7,
      lastVisit: '1 month ago',
    ),
    _PatientData(
      name: 'Ethan Miller',
      age: 48,
      gender: 'Male',
      condition: 'Back Pain',
      address: '753 Ash Ave, Shelbyville',
      contact: '+1 (555) 012-3456',
      secondContact: '+1 (555) 098-7654',
      sessionsAttended: 14,
      lastVisit: '2 months ago',
    ),
    _PatientData(
      name: 'Mia Rodriguez',
      age: 25,
      gender: 'Female',
      condition: 'Eczema',
      address: '951 Poplar St, North Haverbrook',
      contact: '+1 (555) 123-4560',
      secondContact: '+1 (555) 987-6540',
      sessionsAttended: 2,
      lastVisit: '2 months ago',
    ),
    _PatientData(
      name: 'Alexander Moore',
      age: 39,
      gender: 'Male',
      condition: 'Insomnia',
      address: '357 Magnolia Rd, Brockway',
      contact: '+1 (555) 234-5670',
      secondContact: '+1 (555) 876-5430',
      sessionsAttended: 9,
      lastVisit: '3 months ago',
    ),
    _PatientData(
      name: 'Charlotte Taylor',
      age: 44,
      gender: 'Female',
      condition: 'Obesity',
      address: '159 Dogwood Ln, Springfield',
      contact: '+1 (555) 345-6780',
      secondContact: '+1 (555) 765-4320',
      sessionsAttended: 11,
      lastVisit: '3 months ago',
    ),
    _PatientData(
      name: 'Benjamin Anderson',
      age: 51,
      gender: 'Male',
      condition: 'High Cholesterol',
      address: '753 Fir Ave, Capital City',
      contact: '+1 (555) 456-7891',
      secondContact: '+1 (555) 654-3219',
      sessionsAttended: 18,
      lastVisit: '4 months ago',
    ),
    _PatientData(
      name: 'Amelia Jackson',
      age: 36,
      gender: 'Female',
      condition: 'Pregnancy (2nd trimester)',
      address: '852 Redwood St, Ogdenville',
      contact: '+1 (555) 567-8902',
      secondContact: '+1 (555) 543-2108',
      sessionsAttended: 4,
      lastVisit: '5 months ago',
    ),
  ];

  static const double _itemExtent = 78.0;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemExtent: _itemExtent,
      itemCount: _patients.length,
      itemBuilder: (context, index) =>
          _PatientTile(data: _patients[index]),
    );
  }
}

// ---------- PATIENT TILE (navigates with full data) ----------
class _PatientTile extends StatelessWidget {
  final _PatientData data;
  const _PatientTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PatientDetailsPage(
                  name: data.name,
                  age: data.age,
                  gender: data.gender,
                  condition: data.condition,
                  address: data.address,
                  contact: data.contact,
                  secondContact: data.secondContact,
                  sessionsAttended: data.sessionsAttended,
                  lastVisit: data.lastVisit,
                ),
              ),
            );
          },
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.silver.withOpacity(0.2),
                  child: Text(
                    data.name[0],
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        data.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${data.gender[0]}, ${data.age}  •  ${data.lastVisit}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
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

// ---------- UPDATED DATA CLASS ----------
class _PatientData {
  final String name;
  final int age;
  final String gender;
  final String condition;
  final String address;
  final String contact;
  final String secondContact;
  final int sessionsAttended;
  final String lastVisit;

  const _PatientData({
    required this.name,
    required this.age,
    required this.gender,
    required this.condition,
    required this.address,
    required this.contact,
    required this.secondContact,
    required this.sessionsAttended,
    required this.lastVisit,
  });
}