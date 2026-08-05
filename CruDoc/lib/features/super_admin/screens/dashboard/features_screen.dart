import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/enums.dart';
import '../../providers/feature_management_provider.dart';

/// Super Admin Feature Management Screen.
/// Provides a simple Doctor dropdown menu with feature toggle switches inside.
class SuperAdminFeaturesScreen extends ConsumerStatefulWidget {
  const SuperAdminFeaturesScreen({super.key});

  @override
  ConsumerState<SuperAdminFeaturesScreen> createState() =>
      _SuperAdminFeaturesScreenState();
}

class _SuperAdminFeaturesScreenState
    extends ConsumerState<SuperAdminFeaturesScreen> {
  // Sample doctor accounts list
  final List<Map<String, String>> _doctors = const [
    {
      'id': 'doc-991',
      'name': 'Dr. Venom Mhatre',
      'email': 'venom@crudoc.com',
      'clinic': 'Mhatre Healthcare Clinic',
    },
    {
      'id': 'doc-882',
      'name': 'Dr. Smit Mhatre',
      'email': 'smit@crudoc.com',
      'clinic': 'Smit Medical Center',
    },
    {
      'id': 'doc-773',
      'name': 'Dr. Ananya Roy',
      'email': 'ananya@royhealth.com',
      'clinic': 'Roy Specialty Hospital',
    },
    {
      'id': 'doc-664',
      'name': 'Dr. Rajesh Kumar',
      'email': 'rkumar@citycare.com',
      'clinic': 'CityCare Polyclinic',
    },
    {
      'id': 'doc-555',
      'name': 'Dr. Meera Patel',
      'email': 'meera@patelclinic.in',
      'clinic': 'Patel Wellness Center',
    },
  ];

  late String _selectedDoctorId;

  // Track enabled feature modules per doctor (doctorId -> Set of enabled FeatureModules)
  final Map<String, Set<FeatureModule>> _doctorFeatures = {};

  @override
  void initState() {
    super.initState();
    _selectedDoctorId = _doctors.first['id']!;

    // Initialize initial feature toggles for doctors
    _doctorFeatures['doc-991'] = {
      FeatureModule.dashboard,
      FeatureModule.patients,
      FeatureModule.appointments,
      FeatureModule.revenue,
    };
    _doctorFeatures['doc-882'] = {
      FeatureModule.dashboard,
      FeatureModule.patients,
      FeatureModule.appointments,
      FeatureModule.revenue,
      FeatureModule.omnichannelMessaging,
    };
    _doctorFeatures['doc-773'] = {
      FeatureModule.dashboard,
      FeatureModule.patients,
      FeatureModule.appointments,
      FeatureModule.homeVisits,
      FeatureModule.aiAssistant,
    };
    _doctorFeatures['doc-664'] = {
      FeatureModule.dashboard,
      FeatureModule.patients,
      FeatureModule.appointments,
      FeatureModule.revenue,
      FeatureModule.aiAssistant,
      FeatureModule.aiAgenticCalling,
      FeatureModule.omnichannelMessaging,
    };
    _doctorFeatures['doc-555'] = {
      FeatureModule.dashboard,
      FeatureModule.patients,
      FeatureModule.appointments,
      FeatureModule.multiDeviceAccess,
    };
  }

  Set<FeatureModule> _getEnabledModules(String doctorId) {
    return _doctorFeatures[doctorId] ??= {
      FeatureModule.dashboard,
      FeatureModule.patients,
      FeatureModule.appointments,
    };
  }

  void _toggleModule(String doctorId, FeatureModule module, bool value) {
    setState(() {
      final set = _getEnabledModules(doctorId);
      if (value) {
        set.add(module);
      } else {
        set.remove(module);
      }
    });
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
    final featureState = ref.watch(featureManagementProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;
    final selectedDoctor = _doctors.firstWhere(
      (d) => d['id'] == _selectedDoctorId,
      orElse: () => _doctors.first,
    );
    final enabledModules = _getEnabledModules(_selectedDoctorId);
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
              _buildDoctorDropdownCard(context, selectedDoctor, enabledModules),
              const SizedBox(height: 20),

              // 3. Feature Toggles List inside Doctor Container
              _buildFeatureTogglesCard(
                  context, featureState, enabledModules, totalMonthlyPrice),
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
        Text(
          'Doctor Feature Management',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
    Map<String, String> selectedDoctor,
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
                value: _selectedDoctorId,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF64748B), size: 24),
                items: _doctors.map((doctor) {
                  return DropdownMenuItem<String>(
                    value: doctor['id']!,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.12),
                          child: Text(
                            doctor['name']![4].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              doctor['name']!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${doctor['clinic']} • ${doctor['email']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
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
                        _toggleModule(_selectedDoctorId, feature.module, val);
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
