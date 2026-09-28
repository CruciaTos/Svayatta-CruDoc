import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../../config/enums.dart';
import '../../models/doctor_model.dart';
import '../../providers/doctor_provider.dart';
import '../../services/doctor_service.dart';
import 'upgrade_requests_screen.dart';

/// Super Admin Feature Management Screen redesigned into the CruDoc Calm Clinical design system.
/// Displays real doctors from Firestore with interactive module toggle switches categorized into suites.
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
      case 'queue':
      case 'walk_in_queue':
        return FeatureModule.queue;
      case 'dental_suite':
      case 'dental':
      case 'odontogram':
        return FeatureModule.dentalSuite;
      case 'radiology':
      case 'dicom':
      case 'imaging':
        return FeatureModule.radiology;
      case 'rvg_sensor':
      case 'rvg':
      case 'sensor':
        return FeatureModule.rvgSensor;
      case 'ai_scribe_second_read':
      case 'ai_scribe':
      case 'second_read':
        return FeatureModule.aiScribeSecondRead;
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
      case FeatureModule.queue:
        return 'queue';
      case FeatureModule.dentalSuite:
        return 'dental_suite';
      case FeatureModule.radiology:
        return 'radiology';
      case FeatureModule.rvgSensor:
        return 'rvg_sensor';
      case FeatureModule.aiScribeSecondRead:
        return 'ai_scribe_second_read';
    }
  }

  Set<FeatureModule> _getEnabledModules(DoctorModel doctor) {
    if (!_doctorFeatures.containsKey(doctor.id)) {
      final set = <FeatureModule>{};
      for (final modStr in doctor.enabledModules) {
        final mod = _parseModule(modStr);
        if (mod != null) set.add(mod);
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
    final allowMultiDevice = updatedModuleStrings.contains('multi_device_access');

    try {
      setState(() => _isSaving = true);
      await _doctorService.updateDoctor(doctor.id, {
        'enabledModules': updatedModuleStrings,
        'allowMultiDevice': allowMultiDevice,
      });
      ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
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

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final doctorState = ref.watch(doctorListProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    if (doctorState.isLoading && doctorState.doctors.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(48.0), child: CircularProgressIndicator()));
    }

    final doctors = doctorState.doctors;

    if (doctors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CruIcon(CruIcons.patients, size: 48, color: c.label3),
              const SizedBox(height: CruSpace.s16),
              Text(
                'No doctors found in system',
                style: CruType.headline.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s8),
              Text(
                'Create a new doctor account in the Doctors tab to manage their feature permissions.',
                textAlign: TextAlign.center,
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedDoctorId == null || !doctors.any((d) => d.id == _selectedDoctorId)) {
      _selectedDoctorId = doctors.first.id;
    }

    final selectedDoctor = doctors.firstWhere(
      (d) => d.id == _selectedDoctorId,
      orElse: () => doctors.first,
    );

    final enabledModules = _getEnabledModules(selectedDoctor);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          _buildHeader(context),

          const SizedBox(height: CruSpace.s20),

          // 2. Doctor Selector Card
          _buildDoctorSelectorCard(context, doctors, selectedDoctor, enabledModules),

          const SizedBox(height: CruSpace.s24),

          // 3. Categorized Feature Suites
          _buildFeatureSuites(context, selectedDoctor, enabledModules),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final c = context.cru;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Feature Modules & Rollouts',
                style: CruType.largeTitle.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Activate and assign core clinical suites, PACS DICOM viewer, RVG sensor bridges, and Gemini AI scribe.',
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
        if (_isSaving) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: CruSpace.s12),
        ],
        CruButton(
          label: 'Upgrade Requests',
          kind: CruButtonKind.secondary,
          icon: CruIcons.box,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SuperAdminUpgradeRequestsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDoctorSelectorCard(
    BuildContext context,
    List<DoctorModel> doctors,
    DoctorModel selectedDoctor,
    Set<FeatureModule> enabledModules,
  ) {
    final c = context.cru;

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Row(
        children: [
          CruMonogram(name: selectedDoctor.name, size: 44, background: c.track),
          const SizedBox(width: CruSpace.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Active Doctor Target: ', style: CruType.caption.tint(c.label3)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: ShapeDecoration(
                        color: c.accentTint,
                        shape: cruShape(CruRadius.full),
                      ),
                      child: Text(
                        '${enabledModules.length} Modules Active',
                        style: CruType.caption.w600.tabular.tint(c.accentText),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s4),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedDoctor.id,
                    isDense: true,
                    style: CruType.row.tint(c.label),
                    items: doctors.map((doc) {
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text('${doc.name} (${doc.clinicName.isNotEmpty ? doc.clinicName : doc.specialization})'),
                      );
                    }).toList(),
                    onChanged: (id) {
                      if (id != null) setState(() => _selectedDoctorId = id);
                    },
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.full, side: BorderSide(color: c.hairline)),
            ),
            child: Text(
              selectedDoctor.subscriptionPlan.label,
              style: CruType.caption.w600.tint(c.label),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureSuites(
    BuildContext context,
    DoctorModel doctor,
    Set<FeatureModule> enabled,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSuiteSection(
          context,
          title: 'Core Clinical Suite',
          subtitle: 'Essential operational workflows and communication pipelines',
          icon: CruIcons.home,
          modules: [
            FeatureModule.dashboard,
            FeatureModule.appointments,
            FeatureModule.patients,
            FeatureModule.revenue,
            FeatureModule.inventory,
            FeatureModule.queue,
            FeatureModule.omnichannelMessaging,
            FeatureModule.multiDeviceAccess,
          ],
          doctor: doctor,
          enabled: enabled,
        ),
        const SizedBox(height: CruSpace.s20),
        _buildSuiteSection(
          context,
          title: 'Dental Specialization Suite',
          subtitle: 'Chairside charting, FDI/Universal odontogram, and perio records',
          icon: CruIcons.flask,
          modules: [
            FeatureModule.dentalSuite,
            FeatureModule.homeVisits,
          ],
          doctor: doctor,
          enabled: enabled,
        ),
        const SizedBox(height: CruSpace.s20),
        _buildSuiteSection(
          context,
          title: 'Radiology & Imaging Suite',
          subtitle: 'Direct hardware USB sensor bridge and DICOM PACS server links',
          icon: CruIcons.box,
          modules: [
            FeatureModule.radiology,
            FeatureModule.rvgSensor,
          ],
          doctor: doctor,
          enabled: enabled,
        ),
        const SizedBox(height: CruSpace.s20),
        _buildSuiteSection(
          context,
          title: 'Clinical AI Intelligence Suite',
          subtitle: 'Gemini multimodal consultation scribe and 2nd read diagnostic guard',
          icon: CruIcons.sparkle,
          modules: [
            FeatureModule.aiScribeSecondRead,
            FeatureModule.aiAssistant,
            FeatureModule.aiAgenticCalling,
          ],
          doctor: doctor,
          enabled: enabled,
        ),
      ],
    );
  }

  Widget _buildSuiteSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required CruIconData icon,
    required List<FeatureModule> modules,
    required DoctorModel doctor,
    required Set<FeatureModule> enabled,
  }) {
    final c = context.cru;

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accentTint,
                  shape: cruShape(CruRadius.appMark),
                ),
                child: CruIcon(icon, size: 16, color: c.accentText),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CruType.headline.tint(c.label)),
                    Text(subtitle, style: CruType.caption.tint(c.label3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          Divider(height: 1, color: c.hairline),
          for (final mod in modules) ...[
            _buildModuleRow(c, mod, doctor, enabled.contains(mod)),
            Divider(height: 1, color: c.hairline),
          ],
        ],
      ),
    );
  }

  Widget _buildModuleRow(
    CruColors c,
    FeatureModule module,
    DoctorModel doctor,
    bool isEnabled,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(module.label, style: CruType.row.tint(c.label)),
                    const SizedBox(width: CruSpace.s8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: ShapeDecoration(
                        color: isEnabled ? c.greenTint : c.inset,
                        shape: cruShape(CruRadius.full),
                      ),
                      child: Text(
                        isEnabled ? 'ENABLED' : 'INACTIVE',
                        style: CruType.caption.w600.tint(isEnabled ? c.greenText : c.label3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  module.description,
                  style: CruType.caption.tint(c.label2),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            activeTrackColor: c.accent,
            onChanged: (val) => _toggleModule(doctor, module, val),
          ),
        ],
      ),
    );
  }
}
