import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/core/theme/cru_tokens.dart';
import '../../models/platform_settings_model.dart';
import '../../providers/settings_provider.dart';

enum SettingsCategory {
  radiology,
  rvgBridge,
  dentalSuite,
  aiScribe,
  governance,
  storageSync,
}

/// CruDoc Super Admin Platform Configuration & Settings Console.
/// Manages global system toggles, DICOM PACS routing, Direct RVG sensor bridge,
/// Dental Specialty suites, Gemini AI diagnostics, and platform security.
class SuperAdminSettingsScreen extends ConsumerStatefulWidget {
  const SuperAdminSettingsScreen({super.key});

  @override
  ConsumerState<SuperAdminSettingsScreen> createState() =>
      _SuperAdminSettingsScreenState();
}

class _SuperAdminSettingsScreenState
    extends ConsumerState<SuperAdminSettingsScreen> {
  SettingsCategory _selectedCategory = SettingsCategory.radiology;

  // Controllers for text fields
  late TextEditingController _pacsAeController;
  late TextEditingController _pacsPortController;
  late TextEditingController _rvgHostController;
  late TextEditingController _rvgPortController;
  late TextEditingController _rvgTimeoutController;
  late TextEditingController _maintenanceMsgController;
  late TextEditingController _procedureCatalogController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(superAdminSettingsProvider).settings;
    _initControllers(settings);
  }

  void _initControllers(PlatformSettingsModel s) {
    _pacsAeController = TextEditingController(text: s.pacsAeTitle);
    _pacsPortController = TextEditingController(text: s.pacsPort.toString());
    _rvgHostController = TextEditingController(text: s.rvgBridgeHost);
    _rvgPortController = TextEditingController(
      text: s.rvgBridgePort.toString(),
    );
    _rvgTimeoutController = TextEditingController(
      text: s.rvgAcquisitionTimeoutSeconds.toString(),
    );
    _maintenanceMsgController = TextEditingController(
      text: s.maintenanceMessage,
    );
    _procedureCatalogController = TextEditingController(
      text: s.procedureCatalogVersion,
    );
  }

  @override
  void dispose() {
    _pacsAeController.dispose();
    _pacsPortController.dispose();
    _rvgHostController.dispose();
    _rvgPortController.dispose();
    _rvgTimeoutController.dispose();
    _maintenanceMsgController.dispose();
    _procedureCatalogController.dispose();
    super.dispose();
  }

  void _syncControllersWithModel(PlatformSettingsModel s) {
    if (_pacsAeController.text != s.pacsAeTitle) {
      _pacsAeController.text = s.pacsAeTitle;
    }
    if (_pacsPortController.text != s.pacsPort.toString()) {
      _pacsPortController.text = s.pacsPort.toString();
    }
    if (_rvgHostController.text != s.rvgBridgeHost) {
      _rvgHostController.text = s.rvgBridgeHost;
    }
    if (_rvgPortController.text != s.rvgBridgePort.toString()) {
      _rvgPortController.text = s.rvgBridgePort.toString();
    }
    if (_rvgTimeoutController.text !=
        s.rvgAcquisitionTimeoutSeconds.toString()) {
      _rvgTimeoutController.text = s.rvgAcquisitionTimeoutSeconds.toString();
    }
    if (_maintenanceMsgController.text != s.maintenanceMessage) {
      _maintenanceMsgController.text = s.maintenanceMessage;
    }
    if (_procedureCatalogController.text != s.procedureCatalogVersion) {
      _procedureCatalogController.text = s.procedureCatalogVersion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(superAdminSettingsProvider);
    final notifier = ref.read(superAdminSettingsProvider.notifier);
    final isMobile = MediaQuery.of(context).size.width < 800;

    _syncControllersWithModel(state.settings);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Header Bar
            _buildHeader(context, state, notifier, isMobile),
            const SizedBox(height: 20),

            // 2. Status Banners (Maintenance, Success, Error)
            if (state.settings.maintenanceMode) ...[
              _buildMaintenanceWarningBanner(state.settings.maintenanceMessage),
              const SizedBox(height: 16),
            ],
            if (state.successMessage != null) ...[
              _buildAlertBanner(
                message: state.successMessage!,
                isError: false,
                onDismiss: () => notifier.clearMessages(),
              ),
              const SizedBox(height: 16),
            ],
            if (state.errorMessage != null) ...[
              _buildAlertBanner(
                message: state.errorMessage!,
                isError: true,
                onDismiss: () => notifier.clearMessages(),
              ),
              const SizedBox(height: 16),
            ],

            // 3. Category Selector Bar
            _buildCategoryTabs(isMobile),
            const SizedBox(height: 24),

            // 4. Main Category Content Panels
            state.isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(60.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _buildSelectedCategoryContent(
                    context,
                    state,
                    notifier,
                    isMobile,
                  ),
          ],
        ),
      ),
    );
  }

  // ==================== 1. HEADER ====================
  Widget _buildHeader(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'System Configuration',
                            style: TextStyle(
                              fontFamily: AppColors.headingFontFamily,
                              fontSize: isMobile ? 22 : 26,
                              fontWeight: FontWeight.w800,
                              color: AppColors.midnightBlue,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (state.isDirty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFF59E0B),
                                  width: 1,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 3,
                                    backgroundColor: Color(0xFFD97706),
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'Unsaved Changes',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Global governance, PACS DICOM routing, Direct RVG sensor bridge, dental charts, and Gemini AI settings.',
                        style: TextStyle(
                          fontFamily: AppColors.bodyFontFamily,
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isNarrow) ...[
                  if (state.isDirty) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.slateBlue,
                        side: BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => notifier.resetChanges(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  ElevatedButton.icon(
                    icon: state.isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.cloud_done_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                    label: Text(
                      state.isSaving ? 'Deploying...' : 'Save Configuration',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CruRadius.control),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    onPressed: state.isSaving
                        ? null
                        : () => notifier.saveSettings(),
                  ),
                ],
              ],
            ),
            if (isNarrow) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (state.isDirty) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.slateBlue,
                          side: BorderSide(color: AppColors.divider),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              CruRadius.control,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => notifier.resetChanges(),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      icon: state.isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.cloud_done_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                      label: Text(
                        state.isSaving ? 'Saving...' : 'Save Configuration',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            CruRadius.control,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: state.isSaving
                          ? null
                          : () => notifier.saveSettings(),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  // ==================== 2. STATUS & MAINTENANCE BANNERS ====================
  Widget _buildMaintenanceWarningBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(CruRadius.control),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFD97706),
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MAINTENANCE MODE IS ACTIVELY BROADCASTING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBanner({
    required String message,
    required bool isError,
    required VoidCallback onDismiss,
  }) {
    final bgColor = isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5);
    final borderColor = isError
        ? const Color(0xFFFECACA)
        : const Color(0xFFA7F3D0);
    final textColor = isError
        ? const Color(0xFF991B1B)
        : const Color(0xFF065F46);
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(CruRadius.control),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: textColor),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ==================== 3. CATEGORY TABS ====================
  Widget _buildCategoryTabs(bool isMobile) {
    final tabs = [
      (
        SettingsCategory.radiology,
        Icons.camera_alt_outlined,
        'Radiology & DICOM',
      ),
      (SettingsCategory.rvgBridge, Icons.sensors_outlined, 'Direct RVG Bridge'),
      (
        SettingsCategory.dentalSuite,
        Icons.medical_services_outlined,
        'Dental Specialty',
      ),
      (
        SettingsCategory.aiScribe,
        Icons.psychology_outlined,
        'AI Scribe & 2nd Read',
      ),
      (
        SettingsCategory.governance,
        Icons.security_outlined,
        'Security & Lockdown',
      ),
      (SettingsCategory.storageSync, Icons.storage_outlined, 'Database & Sync'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _selectedCategory == tab.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(CruRadius.control),
              onTap: () {
                setState(() {
                  _selectedCategory = tab.$1;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : AppColors.divider,
                  ),
                  boxShadow: const [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.$2,
                      size: 18,
                      color: isSelected ? Colors.white : AppColors.slateBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tab.$3,
                      style: TextStyle(
                        fontFamily: AppColors.bodyFontFamily,
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ==================== 4. CATEGORY CONTENT ROUTING ====================
  Widget _buildSelectedCategoryContent(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    switch (_selectedCategory) {
      case SettingsCategory.radiology:
        return _buildRadiologySection(context, state, notifier, isMobile);
      case SettingsCategory.rvgBridge:
        return _buildRvgBridgeSection(context, state, notifier, isMobile);
      case SettingsCategory.dentalSuite:
        return _buildDentalSuiteSection(context, state, notifier, isMobile);
      case SettingsCategory.aiScribe:
        return _buildAiScribeSection(context, state, notifier, isMobile);
      case SettingsCategory.governance:
        return _buildGovernanceSection(context, state, notifier, isMobile);
      case SettingsCategory.storageSync:
        return _buildStorageSyncSection(context, state, notifier, isMobile);
    }
  }

  // ==================== 5. SECTION: RADIOLOGY & DICOM ====================
  Widget _buildRadiologySection(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    final s = state.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.camera_alt_rounded,
          iconColor: const Color(0xFF8B5CF6),
          title: 'Radiology PACS & DICOM Engine Configuration',
          subtitle:
              'Configure the high-performance DICOM rendering pipeline, PACS listener routing, and progressive slice cache.',
        ),
        const SizedBox(height: 18),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'PACS Server AE Title & Listener Port',
              subtitle: 'DICOM C-STORE and C-MOVE network identity.',
              child: Column(
                children: [
                  _buildTextInput(
                    label: 'Application Entity (AE) Title',
                    controller: _pacsAeController,
                    hint: 'CRUDOC_PACS',
                    onChanged: (val) {
                      notifier.updateSettings(
                        s.copyWith(pacsAeTitle: val.trim()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextInput(
                    label: 'DICOM SCP Inbound Port',
                    controller: _pacsPortController,
                    hint: '11112',
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final p = int.tryParse(val.trim());
                      if (p != null)
                        notifier.updateSettings(s.copyWith(pacsPort: p));
                    },
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'Diagnostic Rendering & Storage Quota',
              subtitle: 'Bit-depth windowing and doctor cloud capacity.',
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: '16-Bit High Bit-Depth Windowing',
                    subtitle:
                        'Apply direct linear window/level contrast LUT on full dynamic range',
                    value: s.highBitDepthRendering,
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(highBitDepthRendering: v),
                      );
                    },
                  ),
                  const Divider(height: 16),
                  _buildSwitchTile(
                    title: 'Fuzzy Progressive Slice Streaming',
                    subtitle:
                        'Instantly display thumbnail slice previews before byte-stream completes',
                    value: s.progressiveStreaming,
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(progressiveStreaming: v),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Multi-Frame CBCT Preload Buffer',
              subtitle:
                  'Number of adjacent axial/sagittal slices kept in active VRAM cache.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Preload Slice Radius:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${s.dicomPreloadSliceCount} slices',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B21A8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: s.dicomPreloadSliceCount.toDouble(),
                    min: 4,
                    max: 64,
                    divisions: 15,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(dicomPreloadSliceCount: v.toInt()),
                      );
                    },
                  ),
                  const Text(
                    'Recommended: 16 for desktop workstations, 8 for lightweight browser tablets.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'Per-Doctor DICOM Cloud Storage Limit',
              subtitle:
                  'Default allocated high-resolution volume quota per clinic.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Allocated Storage Quota:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${s.defaultDoctorStorageQuotaGB.toStringAsFixed(0)} GB',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF5B21B6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: s.defaultDoctorStorageQuotaGB,
                    min: 10,
                    max: 500,
                    divisions: 49,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(defaultDoctorStorageQuotaGB: v),
                      );
                    },
                  ),
                  const Text(
                    'Doctors receive soft warnings at 80% usage and upload blocking at 100%.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 6. SECTION: DIRECT RVG BRIDGE ====================
  Widget _buildRvgBridgeSection(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    final s = state.settings;
    final ping = state.bridgePingResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.sensors_rounded,
          iconColor: const Color(0xFFF59E0B),
          title: 'Direct RVG Sensor Hardware Bridge Configuration',
          subtitle:
              'Manage the local daemon bridge protocol that interacts directly with USB intraoral X-ray sensors.',
        ),
        const SizedBox(height: 18),

        // Live Bridge Status & Diagnostic Panel
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(CruRadius.card),
            border: Border.all(
              color: ping != null
                  ? (ping.isOnline
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444))
                  : AppColors.divider,
              width: ping != null ? 1.5 : 1.0,
            ),
            boxShadow: const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (ping?.isOnline ?? false)
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.router_rounded,
                      color: (ping?.isOnline ?? false)
                          ? const Color(0xFF059669)
                          : const Color(0xFFD97706),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HARDWARE BRIDGE DAEMON CONNECTIVITY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: Color(0xFFB45309),
                          ),
                        ),
                        Text(
                          'Target: ${s.rvgBridgeUrl}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: state.isTestingBridge
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.bolt_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                    label: Text(
                      state.isTestingBridge
                          ? 'Pinging...'
                          : 'Ping Sensor Bridge',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CruRadius.control),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onPressed: state.isTestingBridge
                        ? null
                        : () => notifier.testBridge(),
                  ),
                ],
              ),
              if (ping != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ping.isOnline
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ping.isOnline
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ping.isOnline
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: ping.isOnline
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ping.isOnline
                              ? 'Bridge Online (${ping.latencyMs}ms latency) • Version: ${ping.version ?? "1.0"} • Active Drivers: ${ping.activeSensors.join(", ")}'
                              : 'Bridge Offline • Status: ${ping.statusMessage}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ping.isOnline
                                ? const Color(0xFF065F46)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Bridge Host & Network Port',
              subtitle: 'Local loopback IP and daemon listening port.',
              child: Column(
                children: [
                  _buildTextInput(
                    label: 'Bridge Host Address',
                    controller: _rvgHostController,
                    hint: '127.0.0.1',
                    onChanged: (val) {
                      notifier.updateSettings(
                        s.copyWith(rvgBridgeHost: val.trim()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextInput(
                    label: 'Daemon Port',
                    controller: _rvgPortController,
                    hint: '8766',
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final p = int.tryParse(val.trim());
                      if (p != null)
                        notifier.updateSettings(s.copyWith(rvgBridgePort: p));
                    },
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'Driver Detection & Capture Governance',
              subtitle: 'Fallback behaviors when hardware drivers are absent.',
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'Hardware Driver Auto-Discovery',
                    subtitle:
                        'Scan TWAIN, Vatech, Carestream, Dexis, and Woodpecker sensor DLLs',
                    value: s.autoDiscoverDrivers,
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(autoDiscoverDrivers: v),
                      );
                    },
                  ),
                  const Divider(height: 16),
                  _buildSwitchTile(
                    title: 'Simulated Capture Fallback',
                    subtitle:
                        'Generate synthetic realistic intraoral dental exposures when no sensor is plugged in',
                    value: s.allowSimulatedCaptureFallback,
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(allowSimulatedCaptureFallback: v),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Hardware Exposure Timeout',
              subtitle:
                  'Maximum duration the sensor waits for radiation trigger before canceling.',
              child: Column(
                children: [
                  _buildTextInput(
                    label: 'Acquisition Timeout (Seconds)',
                    controller: _rvgTimeoutController,
                    hint: '45',
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      final t = int.tryParse(val.trim());
                      if (t != null) {
                        notifier.updateSettings(
                          s.copyWith(rvgAcquisitionTimeoutSeconds: t),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Recommended: 45 seconds to allow technician arming and patient positioning.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'Default RVG Calibration Profile',
              subtitle: 'Preset post-capture unsharp masking and gamma curves.',
              child: DropdownButtonFormField<String>(
                initialValue: s.defaultCalibrationProfile,
                decoration: _inputDecoration(label: 'Calibration Curve'),
                items: const [
                  DropdownMenuItem(
                    value: 'High Contrast Dental (16-bit)',
                    child: Text('High Contrast Dental (16-bit)'),
                  ),
                  DropdownMenuItem(
                    value: 'Soft Tissue Endodontic',
                    child: Text('Soft Tissue Endodontic'),
                  ),
                  DropdownMenuItem(
                    value: 'Caries Detection Enhanced',
                    child: Text('Caries Detection Enhanced'),
                  ),
                  DropdownMenuItem(
                    value: 'Linear Raw Sensor Signal',
                    child: Text('Linear Raw Sensor Signal'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.updateSettings(
                      s.copyWith(defaultCalibrationProfile: v),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 7. SECTION: DENTAL SPECIALTY SUITE ====================
  Widget _buildDentalSuiteSection(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    final s = state.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.medical_services_rounded,
          iconColor: const Color(0xFF0EA5E9),
          title: 'Dental Specialty Suite & Charting Parameters',
          subtitle:
              'Global tooth numbering standards, periodontal risk threshold alerts, and treatment planning catalogs.',
        ),
        const SizedBox(height: 18),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Odontogram Numbering System Gate',
              subtitle:
                  'Platform-wide dental notation system applied to clinical charts.',
              child: DropdownButtonFormField<String>(
                initialValue: s.odontogramNumberingSystem,
                decoration: _inputDecoration(
                  label: 'Global Numbering Notation',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'FDI (ISO 3950)',
                    child: Text(
                      'FDI Two-Digit World Dental Standard (ISO 3950)',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Universal (ADA)',
                    child: Text('Universal American Dental Association (1-32)'),
                  ),
                  DropdownMenuItem(
                    value: 'Palmer Notation',
                    child: Text('Palmer Dental Grid Quadrant Notation'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.updateSettings(
                      s.copyWith(odontogramNumberingSystem: v),
                    );
                  }
                },
              ),
            ),
            _buildSettingCard(
              title: 'Pediatric (Primary) Dentition Quick-Toggle',
              subtitle:
                  'Allow instant switching between permanent 32 teeth and deciduous 20 primary teeth.',
              child: _buildSwitchTile(
                title: 'Enable Pediatric Deciduous Chart Mode',
                subtitle:
                    'Doctors can toggle between Adult Permanent and Pediatric Primary Odontograms in one click',
                value: s.enablePediatricDentitionToggle,
                onChanged: (v) {
                  notifier.updateSettings(
                    s.copyWith(enablePediatricDentitionToggle: v),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Periodontal Probing Depth Red-Flag Warning',
              subtitle:
                  'Pocket depth measurement (mm) that triggers yellow/amber warning.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Warning Threshold (Amber):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '≥ ${s.perioWarningDepthMm} mm',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: s.perioWarningDepthMm.toDouble(),
                    min: 3,
                    max: 6,
                    divisions: 3,
                    activeColor: const Color(0xFFF59E0B),
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(perioWarningDepthMm: v.toInt()),
                      );
                    },
                  ),
                  const Text(
                    'Standard AAP guideline recommends 4 mm as the threshold for early pocketing.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'Periodontal Severe Pocket Alert',
              subtitle:
                  'Deep pocket measurement (mm) that triggers red alert and surgical referral prompt.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Severe Threshold (Red Alert):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '≥ ${s.perioSevereDepthMm} mm',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: s.perioSevereDepthMm.toDouble(),
                    min: 5,
                    max: 10,
                    divisions: 5,
                    activeColor: const Color(0xFFEF4444),
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(perioSevereDepthMm: v.toInt()),
                      );
                    },
                  ),
                  const Text(
                    'Probing depths of 6 mm or greater denote advanced periodontitis.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSettingCard(
          title: 'Dental Procedure Code Catalog Version',
          subtitle:
              'Global CDT / ADA clinical coding scheme deployed to clinics.',
          child: _buildTextInput(
            label: 'Procedure Catalog Schema Version',
            controller: _procedureCatalogController,
            hint: 'CDT-2026.1',
            onChanged: (val) {
              notifier.updateSettings(
                s.copyWith(procedureCatalogVersion: val.trim()),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== 8. SECTION: AI & MEDICAL SCRIBE ====================
  Widget _buildAiScribeSection(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    final s = state.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.psychology_rounded,
          iconColor: const Color(0xFFD946EF),
          title: 'AI Ambient Medical Scribe & Radiology Second Read',
          subtitle:
              'Configure the Google Gemini model engine, confidence gate for radiologic second opinions, and patient privacy redactions.',
        ),
        const SizedBox(height: 18),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Primary Google Gemini LLM Engine',
              subtitle:
                  'Backbone model utilized for real-time transcription and clinical summaries.',
              child: DropdownButtonFormField<String>(
                initialValue: s.geminiModel,
                decoration: _inputDecoration(label: 'Gemini Model'),
                items: const [
                  DropdownMenuItem(
                    value: 'gemini-2.5-flash',
                    child: Text(
                      'Gemini 2.5 Flash (Ultra-Low Latency & High Speed)',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'gemini-2.5-pro',
                    child: Text(
                      'Gemini 2.5 Pro (Deep Clinical Reasoning & Multimodal)',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'gemini-1.5-flash',
                    child: Text('Gemini 1.5 Flash (Legacy Fast Engine)'),
                  ),
                  DropdownMenuItem(
                    value: 'gemini-1.5-pro',
                    child: Text('Gemini 1.5 Pro (Legacy Comprehensive)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.updateSettings(s.copyWith(geminiModel: v));
                  }
                },
              ),
            ),
            _buildSettingCard(
              title: 'Radiology AI Second Read Confidence Threshold',
              subtitle:
                  'Minimum confidence score required before presenting an AI diagnostic finding.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Minimum Confidence Gate:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF4FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(s.aiSecondReadConfidenceThreshold * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFC026D3),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: s.aiSecondReadConfidenceThreshold,
                    min: 0.50,
                    max: 0.99,
                    divisions: 49,
                    activeColor: const Color(0xFFD946EF),
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(aiSecondReadConfidenceThreshold: v),
                      );
                    },
                  ),
                  const Text(
                    'High threshold (85%+) minimizes false positives while capturing significant radiolucencies.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Ambient Audio Streaming Chunk Buffer',
              subtitle:
                  'Audio packet duration uploaded to Gemini transcription stream.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Audio Chunk Duration:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${s.ambientScribeAudioChunkSeconds} seconds',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: s.ambientScribeAudioChunkSeconds.toDouble(),
                    min: 10,
                    max: 60,
                    divisions: 10,
                    activeColor: const Color(0xFF2563EB),
                    onChanged: (v) {
                      notifier.updateSettings(
                        s.copyWith(ambientScribeAudioChunkSeconds: v.toInt()),
                      );
                    },
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'HIPAA & Privacy Data Protections',
              subtitle:
                  'Automated de-identification and clinical note structuring.',
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'Auto-Format to Structured SOAP Notes',
                    subtitle:
                        'Automatically convert doctor-patient dialogue into Subjective, Objective, Assessment, Plan',
                    value: s.autoSoapNotes,
                    onChanged: (v) {
                      notifier.updateSettings(s.copyWith(autoSoapNotes: v));
                    },
                  ),
                  const Divider(height: 16),
                  _buildSwitchTile(
                    title: 'De-identify Patient PII in AI Payloads',
                    subtitle:
                        'Strip patient names, phone numbers, and addresses prior to sending to LLM APIs',
                    value: s.redactPatientPii,
                    onChanged: (v) {
                      notifier.updateSettings(s.copyWith(redactPatientPii: v));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 9. SECTION: GOVERNANCE & SECURITY ====================
  Widget _buildGovernanceSection(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    final s = state.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.security_rounded,
          iconColor: const Color(0xFFEF4444),
          title: 'Platform Governance & Emergency Security Controls',
          subtitle:
              'Manage system maintenance broadcast banners, emergency read-only lockdowns, and compliance policies.',
        ),
        const SizedBox(height: 18),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Maintenance Mode Banner',
              subtitle:
                  'Display high-priority broadcast banner across all active web & desktop shells.',
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'Activate Platform Maintenance Mode',
                    subtitle:
                        'Shows alert banner informing doctors of upcoming updates or maintenance',
                    value: s.maintenanceMode,
                    activeColor: const Color(0xFFF59E0B),
                    onChanged: (v) {
                      notifier.updateSettings(s.copyWith(maintenanceMode: v));
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextInput(
                    label: 'Broadcast Banner Message',
                    controller: _maintenanceMsgController,
                    hint: 'System maintenance scheduled in 15 minutes...',
                    onChanged: (val) {
                      notifier.updateSettings(
                        s.copyWith(maintenanceMessage: val.trim()),
                      );
                    },
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'Emergency Read-Only Lockdown',
              subtitle:
                  'Freeze all write/edit operations during database migrations or incidents.',
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'Enforce Read-Only Lockdown',
                    subtitle:
                        'Blocks all mutations, appointments, prescriptions, and billing across clinics',
                    value: s.emergencyReadOnlyLockdown,
                    activeColor: const Color(0xFFEF4444),
                    onChanged: (v) {
                      _confirmActionDialog(
                        context: context,
                        title: v
                            ? 'Enable Emergency Lockdown?'
                            : 'Disable Lockdown?',
                        content: v
                            ? 'All clinics will be placed into read-only mode immediately. Doctors will NOT be able to save new clinical notes or bills.'
                            : 'This will restore write operations and allow clinics to resume normal mutations.',
                        confirmText: v
                            ? 'Enable Lockdown'
                            : 'Restore Operations',
                        isDestructive: v,
                        onConfirm: () {
                          notifier.updateSettings(
                            s.copyWith(emergencyReadOnlyLockdown: v),
                          );
                        },
                      );
                    },
                  ),
                  const Divider(height: 16),
                  _buildSwitchTile(
                    title: 'Mandatory Two-Factor Auth (2FA)',
                    subtitle:
                        'Enforce OTP verification for all staff accounts and doctor logins',
                    value: s.enforce2FA,
                    onChanged: (v) {
                      notifier.updateSettings(s.copyWith(enforce2FA: v));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Admin Session Inactivity Timeout',
              subtitle:
                  'Automatically invalidate super admin session tokens after idle duration.',
              child: DropdownButtonFormField<int>(
                initialValue: s.sessionTimeoutMinutes,
                decoration: _inputDecoration(label: 'Timeout Interval'),
                items: const [
                  DropdownMenuItem(
                    value: 15,
                    child: Text('15 Minutes (High Security)'),
                  ),
                  DropdownMenuItem(
                    value: 30,
                    child: Text('30 Minutes (Standard)'),
                  ),
                  DropdownMenuItem(
                    value: 60,
                    child: Text('60 Minutes (Extended)'),
                  ),
                  DropdownMenuItem(value: 120, child: Text('2 Hours')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.updateSettings(
                      s.copyWith(sessionTimeoutMinutes: v),
                    );
                  }
                },
              ),
            ),
            _buildSettingCard(
              title: 'Audit Log Retention Policy',
              subtitle:
                  'Regulatory compliance period for immutable administrator audit trails.',
              child: DropdownButtonFormField<int>(
                initialValue: s.auditLogRetentionYears,
                decoration: _inputDecoration(label: 'Retention Horizon'),
                items: const [
                  DropdownMenuItem(value: 3, child: Text('3 Years')),
                  DropdownMenuItem(
                    value: 5,
                    child: Text('5 Years (NABH Standard)'),
                  ),
                  DropdownMenuItem(
                    value: 7,
                    child: Text('7 Years (HIPAA Compliance)'),
                  ),
                  DropdownMenuItem(
                    value: 10,
                    child: Text('10 Years (Permanent Medical Record)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.updateSettings(
                      s.copyWith(auditLogRetentionYears: v),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 10. SECTION: STORAGE & SYNC ====================
  Widget _buildStorageSyncSection(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
    bool isMobile,
  ) {
    final s = state.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.storage_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'Database Storage & Background Sync Infrastructure',
          subtitle:
              'Manage SQLite client cache compaction, Firestore background polling, and temporary capture cleanup.',
        ),
        const SizedBox(height: 18),
        _buildGridRow(
          isMobile: isMobile,
          children: [
            _buildSettingCard(
              title: 'Client Database Cache Compaction',
              subtitle:
                  'Trigger optimization and defragmentation of local SQLite indexes.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Compacting frees unallocated disk sectors, optimizes B-Trees, and accelerates DICOM thumbnail queries.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: state.isCompacting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.cleaning_services_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                    label: Text(
                      state.isCompacting
                          ? 'Compacting...'
                          : 'Compact Cache & Optimize Indexes',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CruRadius.control),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onPressed: state.isCompacting
                        ? null
                        : () => notifier.compactCache(),
                  ),
                ],
              ),
            ),
            _buildSettingCard(
              title: 'Purge Temporary RVG Captures',
              subtitle:
                  'Automatically purge raw unprocessed sensor frames older than N days.',
              child: DropdownButtonFormField<int>(
                initialValue: s.purgeTempCapturesAfterDays,
                decoration: _inputDecoration(label: 'Auto-Purge Threshold'),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 Days')),
                  DropdownMenuItem(value: 14, child: Text('14 Days (Default)')),
                  DropdownMenuItem(value: 30, child: Text('30 Days')),
                  DropdownMenuItem(value: 90, child: Text('90 Days')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    notifier.updateSettings(
                      s.copyWith(purgeTempCapturesAfterDays: v),
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSettingCard(
          title: 'Cloud Real-Time Sync Polling Interval',
          subtitle:
              'Frequency of background sync pulses between desktop shell and Firestore backend.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sync Interval Frequency:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Every ${s.syncIntervalSeconds}s',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: s.syncIntervalSeconds.toDouble(),
                min: 10,
                max: 120,
                divisions: 11,
                activeColor: const Color(0xFF10B981),
                onChanged: (v) {
                  notifier.updateSettings(
                    s.copyWith(syncIntervalSeconds: v.toInt()),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== UI BUILDER HELPERS ====================

  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppColors.headingFontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.midnightBlue,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridRow({
    required bool isMobile,
    required List<Widget> children,
  }) {
    if (isMobile) {
      return Column(
        children: children
            .map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 14.0),
                child: c,
              ),
            )
            .toList(),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children
          .map(
            (c) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: c,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(CruRadius.card),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.midnightBlue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color activeColor = const Color(0xFF2563EB),
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeTrackColor: activeColor,
          activeThumbColor: Colors.white,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTextInput({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label: label, hint: hint),
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }

  InputDecoration _inputDecoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CruRadius.control),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CruRadius.control),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CruRadius.control),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
    );
  }

  void _confirmActionDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    required bool isDestructive,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(content),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CruRadius.control),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }
}
