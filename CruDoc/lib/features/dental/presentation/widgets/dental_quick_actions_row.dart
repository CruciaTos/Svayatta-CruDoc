import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import '../dental_patient_details_screen.dart';
import '../dental_procedure_catalog_screen.dart';
import '../dental_inventory_screen.dart';
import '../dental_sterilization_screen.dart';

const Color _accentTeal = Color(0xFF0D9488);
const Color _accentTealLight = Color(0xFFCCFBF1);

/// Dental Specialization Quick Actions Row for Dashboard.
///
/// Connects the 4 dental quick action items defined in [DoctorSpecialty.dentist]:
/// 1. Tooth Chart (opens patient picker to view patient's Odontogram)
/// 2. Procedure Log (opens dental procedure catalog)
/// 3. Sterilization (opens autoclave cycle compliance log)
/// 4. Dental Inv. (opens dental consumable inventory & stock manager)
class DentalQuickActionsRow extends ConsumerWidget {
  const DentalQuickActionsRow({super.key});

  void _openToothChartPicker(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.read(patientsStreamProvider);
    final patients = patientsAsync.maybeWhen(data: (l) => l, orElse: () => []);

    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a patient first to view tooth chart.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  'Select Patient for Tooth Chart',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: patients.length,
                  itemBuilder: (context, i) {
                    final p = patients[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: _accentTealLight,
                        child: Icon(Icons.person, color: _accentTeal, size: 20),
                      ),
                      title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('ID: ${p.id.substring(0, p.id.length > 8 ? 8 : p.id.length)}'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DentalPatientDetailsScreen(patient: p),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _DentalAction(
        label: 'Tooth Chart',
        icon: Icons.sentiment_satisfied_alt_rounded,
        onTap: () => _openToothChartPicker(context, ref),
      ),
      _DentalAction(
        label: 'Procedure Log',
        icon: Icons.medical_services_outlined,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DentalProcedureCatalogScreen()),
          );
        },
      ),
      _DentalAction(
        label: 'Sterilization',
        icon: Icons.clean_hands_rounded,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DentalSterilizationScreen()),
          );
        },
      ),
      _DentalAction(
        label: 'Dental Inv.',
        icon: Icons.inventory_2_outlined,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DentalInventoryScreen()),
          );
        },
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentTeal.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: _accentTeal.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stars_rounded, size: 16, color: _accentTeal),
              SizedBox(width: 6),
              Text(
                'DENTAL QUICK ACTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _accentTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 36) / 4;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: actions.map((act) {
                  return SizedBox(
                    width: itemWidth.clamp(74.0, 120.0),
                    child: InkWell(
                      onTap: act.onTap,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: _accentTealLight,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(act.icon, size: 20, color: _accentTeal),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              act.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DentalAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _DentalAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}
