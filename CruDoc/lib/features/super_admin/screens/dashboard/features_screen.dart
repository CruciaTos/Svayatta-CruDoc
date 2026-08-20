import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/enums.dart';
import '../../models/doctor_model.dart';
import '../../providers/doctor_provider.dart';
import '../../providers/feature_management_provider.dart';
import '../../services/doctor_service.dart';
import 'upgrade_requests_screen.dart';

/// Super Admin Feature Management Screen.
/// Displays real doctors from Firestore with interactive feature toggle switches.
class SuperAdminFeaturesScreen extends ConsumerStatefulWidget {
  const SuperAdminFeaturesScreen({super.key});

  @override
  ConsumerState<SuperAdminFeaturesScreen> createState() =>
      _SuperAdminFeaturesScreenState();
}

class _SuperAdminFeaturesScreenState
    extends ConsumerState<SuperAdminFeaturesScreen> {
  String? _selectedDoctorId;
  final Map<String, Set<FeatureModule>> _doctorFeatures = {};
  final SuperAdminDoctorService _doctorService = SuperAdminDoctorService();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
    });
  }

  FeatureModule? _parseModule(String str) {
    final clean = str.trim().toLowerCase();
    switch (clean) {
      case 'dashboard':
        return FeatureModule.dashboard;
      case 'revenue':
      case 'revenue_page':
        return FeatureModule.revenue;
      case 'patients':
      case 'patient_page':
        return FeatureModule.patients;
      case 'appointments':
      case 'appointment':
        return FeatureModule.appointments;
      case 'inventory':
      case 'inventory_management':
        return FeatureModule.inventory;
      case 'home_visits':
      case 'visitation':
        return FeatureModule.homeVisits;
      case 'ai_assistant':
        return FeatureModule.aiAssistant;
      case 'ai_agentic_calling':
        return FeatureModule.aiAgenticCalling;
      case 'omnichannel_messaging':
      case 'whatsapp_messaging':
        return FeatureModule.omnichannelMessaging;
      case 'multi_device_access':
        return FeatureModule.multiDeviceAccess;
      default:
        return null;
    }
  }

  String _moduleToString(FeatureModule module) {
    switch (module) {
      case FeatureModule.dashboard:
        return 'dashboard';
      case FeatureModule.revenue:
        return 'revenue';
      case FeatureModule.patients:
        return 'patients';
      case FeatureModule.appointments:
        return 'appointments';
      case FeatureModule.inventory:
        return 'inventory';
      case FeatureModule.homeVisits:
        return 'home_visits';
      case FeatureModule.aiAssistant:
        return 'ai_assistant';
      case FeatureModule.aiAgenticCalling:
        return 'ai_agentic_calling';
      case FeatureModule.omnichannelMessaging:
        return 'omnichannel_messaging';
      case FeatureModule.multiDeviceAccess:
        return 'multi_device_access';
    }
  }

  Set<FeatureModule> _getEnabledModules(DoctorModel doctor) {
    if (!_doctorFeatures.containsKey(doctor.id)) {
      final set = <FeatureModule>{};
      for (final modStr in doctor.enabledModules) {
        final parsed = _parseModule(modStr);
        if (parsed != null) set.add(parsed);
      }
      _doctorFeatures[doctor.id] = set;
    }
    return _doctorFeatures[doctor.id]!;
  }

  Future<void> _toggleModule(DoctorModel doctor, FeatureModule module, bool value) async {
    final set = _getEnabledModules(doctor);
    setState(() {
      if (value) {
        set.add(module);
      } else {
        set.remove(module);
      }
    });

    final updatedModuleStrings = set.map(_moduleToString).toList();

    try {
      setState(() => _isSaving = true);
      await _doctorService.updateDoctor(doctor.id, {
        'enabledModules': updatedModuleStrings,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${module.label} updated for ${doctor.name}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update feature: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  double _calculateMonthlyTotal(Set<FeatureModule> enabled) {
    double total = 0;
    for (final module in enabled) {
      total += module.defaultAddonPrice;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final doctorState = ref.watch(doctorListProvider);
    final featureState = ref.watch(featureManagementProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    if (doctorState.isLoading && doctorState.doctors.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final doctors = doctorState.doctors;

    if (doctors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'No doctors found in system',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a new doctor account in the Doctors tab to manage their feature permissions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // Ensure selected doctor exists
    if (_selectedDoctorId == null || !doctors.any((d) => d.id == _selectedDoctorId)) {
      _selectedDoctorId = doctors.first.id;
    }

    final selectedDoctor = doctors.firstWhere(
      (d) => d.id == _selectedDoctorId,
      orElse: () => doctors.first,
    );

    final enabledModules = _getEnabledModules(selectedDoctor);
    final totalMonthlyPrice = _calculateMonthlyTotal(enabledModules);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              _buildHeader(context),
              const SizedBox(height: 20),

              // 2. Doctor Selector Dropdown Menu Card
              _buildDoctorDropdownCard(context, doctors, selectedDoctor, enabledModules),
              const SizedBox(height: 20),

              // 3. Feature Toggles List inside Doctor Container
              _buildFeatureTogglesCard(
                context,
                selectedDoctor,
                featureState,
                enabledModules,
                totalMonthlyPrice,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 1. HEADER ====================
  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Doctor Feature Management',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            if (_isSaving) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
            ],
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SuperAdminUpgradeRequestsScreen(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E78FF),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.inbox_rounded, size: 18),
              label: const Text(
                'Upgrade Requests',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Select a doctor from the drop-down menu to enable or disable individual feature modules.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

  // ==================== 2. DOCTOR DROPDOWN CARD ====================
  Widget _buildDoctorDropdownCard(
    BuildContext context,
    List<DoctorModel> doctors,
    DoctorModel selectedDoctor,
    Set<FeatureModule> enabledModules,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin_rounded,
                  color: Color(0xFF8B5CF6), size: 22),
              const SizedBox(width: 8),
              const Text(
                'SELECT DOCTOR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8B5CF6),
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${enabledModules.length} Active Features',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dropdown Menu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedDoctor.id,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF64748B), size: 24),
                items: doctors.map((doctor) {
                  final initialLetter = doctor.name.isNotEmpty ? doctor.name[0].toUpperCase() : 'D';
                  return DropdownMenuItem<String>(
                    value: doctor.id,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.12),
                          child: Text(
                            initialLetter,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                doctor.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${doctor.clinicName.isNotEmpty ? doctor.clinicName : "Clinic"} • ${doctor.email}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedDoctorId = val;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 3. FEATURE TOGGLES LIST ====================
  Widget _buildFeatureTogglesCard(
    BuildContext context,
    DoctorModel selectedDoctor,
    FeatureManagementState state,
    Set<FeatureModule> enabledModules,
    double totalMonthlyPrice,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.toggle_on_rounded,
                    color: Color(0xFF2563EB), size: 22),
                const SizedBox(width: 8),
                const Text(
                  'FEATURE MODULE TOGGLES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2563EB),
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Text(
                  'Monthly Rate: ',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  '\$${totalMonthlyPrice.toStringAsFixed(2)}/mo',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),

          // Toggles List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.features.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey.withValues(alpha: 0.1),
            ),
            itemBuilder: (context, index) {
              final feature = state.features[index];
              final isEnabled = enabledModules.contains(feature.module);

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    // Module Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? const Color(0xFF10B981).withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _moduleIcon(feature.module),
                        color: isEnabled
                            ? const Color(0xFF10B981)
                            : Colors.grey[400],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Module Title + Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                feature.module.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isEnabled
                                      ? null
                                      : Colors.grey[500],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: feature.monthlyPrice == 0
                                      ? const Color(0xFFECFDF5)
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: feature.monthlyPrice == 0
                                        ? const Color(0xFFA7F3D0)
                                        : const Color(0xFFBFDBFE),
                                  ),
                                ),
                                child: Text(
                                  feature.monthlyPrice == 0
                                      ? 'Free'
                                      : '+\$${feature.monthlyPrice.toStringAsFixed(0)}/mo',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: feature.monthlyPrice == 0
                                        ? const Color(0xFF047857)
                                        : const Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            feature.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: isEnabled
                                  ? Colors.grey[600]
                                  : Colors.grey[400],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Toggle Switch
                    Switch(
                      value: isEnabled,
                      onChanged: (val) {
                        _toggleModule(selectedDoctor, feature.module, val);
                      },
                      activeThumbColor: const Color(0xFF10B981),
                    ),
                  ],
                ),
              );
            },
          ),

          // Card Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(
                top: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Calculated Subscription Rate:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  '\$${totalMonthlyPrice.toStringAsFixed(2)} / month',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPERS ====================
  IconData _moduleIcon(FeatureModule module) {
    switch (module) {
      case FeatureModule.dashboard:
        return Icons.dashboard_rounded;
      case FeatureModule.revenue:
        return Icons.account_balance_wallet_rounded;
      case FeatureModule.patients:
        return Icons.people_alt_rounded;
      case FeatureModule.appointments:
        return Icons.calendar_month_rounded;
      case FeatureModule.inventory:
        return Icons.inventory_2_rounded;
      case FeatureModule.homeVisits:
        return Icons.home_work_rounded;
      case FeatureModule.aiAssistant:
        return Icons.auto_awesome_rounded;
      case FeatureModule.aiAgenticCalling:
        return Icons.phone_in_talk_rounded;
      case FeatureModule.omnichannelMessaging:
        return Icons.mark_chat_read_rounded;
      case FeatureModule.multiDeviceAccess:
        return Icons.devices_rounded;
    }
  }
}
