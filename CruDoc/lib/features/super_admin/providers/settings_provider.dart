import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/platform_settings_model.dart';
import '../services/settings_service.dart';

class SettingsState {
  final PlatformSettingsModel settings;
  final PlatformSettingsModel originalSettings;
  final bool isLoading;
  final bool isSaving;
  final bool isTestingBridge;
  final bool isCompacting;
  final BridgePingResult? bridgePingResult;
  final String? errorMessage;
  final String? successMessage;

  const SettingsState({
    this.settings = const PlatformSettingsModel(),
    this.originalSettings = const PlatformSettingsModel(),
    this.isLoading = false,
    this.isSaving = false,
    this.isTestingBridge = false,
    this.isCompacting = false,
    this.bridgePingResult,
    this.errorMessage,
    this.successMessage,
  });

  bool get isDirty =>
      settings.pacsAeTitle != originalSettings.pacsAeTitle ||
      settings.pacsPort != originalSettings.pacsPort ||
      settings.enableCStoreAutoIngest !=
          originalSettings.enableCStoreAutoIngest ||
      settings.dicomPreloadSliceCount !=
          originalSettings.dicomPreloadSliceCount ||
      settings.highBitDepthRendering !=
          originalSettings.highBitDepthRendering ||
      settings.progressiveStreaming != originalSettings.progressiveStreaming ||
      settings.defaultDoctorStorageQuotaGB !=
          originalSettings.defaultDoctorStorageQuotaGB ||
      settings.rvgBridgeHost != originalSettings.rvgBridgeHost ||
      settings.rvgBridgePort != originalSettings.rvgBridgePort ||
      settings.rvgAcquisitionTimeoutSeconds !=
          originalSettings.rvgAcquisitionTimeoutSeconds ||
      settings.allowSimulatedCaptureFallback !=
          originalSettings.allowSimulatedCaptureFallback ||
      settings.autoDiscoverDrivers != originalSettings.autoDiscoverDrivers ||
      settings.defaultCalibrationProfile !=
          originalSettings.defaultCalibrationProfile ||
      settings.odontogramNumberingSystem !=
          originalSettings.odontogramNumberingSystem ||
      settings.enablePediatricDentitionToggle !=
          originalSettings.enablePediatricDentitionToggle ||
      settings.perioWarningDepthMm != originalSettings.perioWarningDepthMm ||
      settings.perioSevereDepthMm != originalSettings.perioSevereDepthMm ||
      settings.procedureCatalogVersion !=
          originalSettings.procedureCatalogVersion ||
      settings.geminiModel != originalSettings.geminiModel ||
      settings.aiSecondReadConfidenceThreshold !=
          originalSettings.aiSecondReadConfidenceThreshold ||
      settings.ambientScribeAudioChunkSeconds !=
          originalSettings.ambientScribeAudioChunkSeconds ||
      settings.autoSoapNotes != originalSettings.autoSoapNotes ||
      settings.redactPatientPii != originalSettings.redactPatientPii ||
      settings.maintenanceMode != originalSettings.maintenanceMode ||
      settings.maintenanceMessage != originalSettings.maintenanceMessage ||
      settings.emergencyReadOnlyLockdown !=
          originalSettings.emergencyReadOnlyLockdown ||
      settings.enforce2FA != originalSettings.enforce2FA ||
      settings.sessionTimeoutMinutes !=
          originalSettings.sessionTimeoutMinutes ||
      settings.auditLogRetentionYears !=
          originalSettings.auditLogRetentionYears ||
      settings.syncIntervalSeconds != originalSettings.syncIntervalSeconds ||
      settings.purgeTempCapturesAfterDays !=
          originalSettings.purgeTempCapturesAfterDays;

  SettingsState copyWith({
    PlatformSettingsModel? settings,
    PlatformSettingsModel? originalSettings,
    bool? isLoading,
    bool? isSaving,
    bool? isTestingBridge,
    bool? isCompacting,
    BridgePingResult? bridgePingResult,
    String? errorMessage,
    String? successMessage,
    bool clearErrors = false,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      originalSettings: originalSettings ?? this.originalSettings,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isTestingBridge: isTestingBridge ?? this.isTestingBridge,
      isCompacting: isCompacting ?? this.isCompacting,
      bridgePingResult: bridgePingResult ?? this.bridgePingResult,
      errorMessage: clearErrors ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearErrors
          ? null
          : (successMessage ?? this.successMessage),
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  late final SuperAdminSettingsService _service;

  @override
  SettingsState build() {
    _service = SuperAdminSettingsService();
    Future.microtask(() => loadSettings());
    return const SettingsState(isLoading: true);
  }

  Future<void> loadSettings() async {
    state = state.copyWith(isLoading: true, clearErrors: true);
    try {
      final settings = await _service.getPlatformSettings();
      state = state.copyWith(
        settings: settings,
        originalSettings: settings,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load platform settings: ${e.toString()}',
      );
    }
  }

  void updateSettings(PlatformSettingsModel newSettings) {
    state = state.copyWith(settings: newSettings, clearErrors: true);
  }

  void resetChanges() {
    state = state.copyWith(settings: state.originalSettings, clearErrors: true);
  }

  Future<bool> saveSettings() async {
    state = state.copyWith(isSaving: true, clearErrors: true);
    try {
      await _service.savePlatformSettings(state.settings);
      state = state.copyWith(
        originalSettings: state.settings,
        isSaving: false,
        successMessage:
            'Configuration saved and deployed across CruDoc platform.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save configuration: ${e.toString()}',
      );
      return false;
    }
  }

  Future<void> testBridge() async {
    state = state.copyWith(isTestingBridge: true, clearErrors: true);
    try {
      final res = await _service.testRvgBridge(
        host: state.settings.rvgBridgeHost,
        port: state.settings.rvgBridgePort,
      );
      state = state.copyWith(isTestingBridge: false, bridgePingResult: res);
    } catch (e) {
      state = state.copyWith(
        isTestingBridge: false,
        bridgePingResult: BridgePingResult(
          isOnline: false,
          latencyMs: 0,
          statusMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> compactCache() async {
    state = state.copyWith(isCompacting: true, clearErrors: true);
    try {
      final res = await _service.compactCache();
      state = state.copyWith(
        isCompacting: false,
        successMessage:
            'Compacted storage: freed ${res['freedMB']} MB, optimized ${res['indexesOptimized']} indexes.',
      );
    } catch (e) {
      state = state.copyWith(
        isCompacting: false,
        errorMessage: 'Failed to compact cache: ${e.toString()}',
      );
    }
  }

  void clearMessages() {
    state = state.copyWith(clearErrors: true);
  }
}

final superAdminSettingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
