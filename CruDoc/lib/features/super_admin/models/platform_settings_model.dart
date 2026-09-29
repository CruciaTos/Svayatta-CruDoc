import 'package:cloud_firestore/cloud_firestore.dart';

/// Platform-wide configuration settings for the CruDoc Super Admin console.
/// Governs Radiology & DICOM engine, Direct RVG Sensor Bridge, Dental Specialty Suite,
/// AI Diagnostic & Scribe Suite, Security Governance, and Storage Sync.
class PlatformSettingsModel {
  // --- 1. Radiology & DICOM Engine ---
  final String pacsAeTitle;
  final int pacsPort;
  final bool enableCStoreAutoIngest;
  final int dicomPreloadSliceCount;
  final bool highBitDepthRendering;
  final bool progressiveStreaming;
  final double defaultDoctorStorageQuotaGB;

  // --- 2. Direct RVG Sensor Hardware Bridge ---
  final String rvgBridgeHost;
  final int rvgBridgePort;
  final int rvgAcquisitionTimeoutSeconds;
  final bool allowSimulatedCaptureFallback;
  final bool autoDiscoverDrivers;
  final String defaultCalibrationProfile;

  // --- 3. Dental Specialty Suite ---
  final String
  odontogramNumberingSystem; // 'FDI (ISO 3950)', 'Universal (ADA)', 'Palmer'
  final bool enablePediatricDentitionToggle;
  final int perioWarningDepthMm;
  final int perioSevereDepthMm;
  final String procedureCatalogVersion;

  // --- 4. AI Diagnostic & Medical Scribe ---
  final String
  geminiModel; // 'gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-1.5-flash'
  final double aiSecondReadConfidenceThreshold;
  final int ambientScribeAudioChunkSeconds;
  final bool autoSoapNotes;
  final bool redactPatientPii;

  // --- 5. Platform Governance & Security ---
  final bool maintenanceMode;
  final String maintenanceMessage;
  final bool emergencyReadOnlyLockdown;
  final bool enforce2FA;
  final int sessionTimeoutMinutes;
  final int auditLogRetentionYears;

  // --- 6. Sync & Storage Infrastructure ---
  final int syncIntervalSeconds;
  final int purgeTempCapturesAfterDays;
  final DateTime? lastModified;
  final String? modifiedBy;

  const PlatformSettingsModel({
    this.pacsAeTitle = 'CRUDOC_PACS',
    this.pacsPort = 11112,
    this.enableCStoreAutoIngest = true,
    this.dicomPreloadSliceCount = 16,
    this.highBitDepthRendering = true,
    this.progressiveStreaming = true,
    this.defaultDoctorStorageQuotaGB = 50.0,
    this.rvgBridgeHost = '127.0.0.1',
    this.rvgBridgePort = 8766,
    this.rvgAcquisitionTimeoutSeconds = 45,
    this.allowSimulatedCaptureFallback = true,
    this.autoDiscoverDrivers = true,
    this.defaultCalibrationProfile = 'High Contrast Dental (16-bit)',
    this.odontogramNumberingSystem = 'FDI (ISO 3950)',
    this.enablePediatricDentitionToggle = true,
    this.perioWarningDepthMm = 4,
    this.perioSevereDepthMm = 6,
    this.procedureCatalogVersion = 'CDT-2026.1',
    this.geminiModel = 'gemini-2.5-flash',
    this.aiSecondReadConfidenceThreshold = 0.85,
    this.ambientScribeAudioChunkSeconds = 30,
    this.autoSoapNotes = true,
    this.redactPatientPii = true,
    this.maintenanceMode = false,
    this.maintenanceMessage =
        'System maintenance in progress. Please save your work.',
    this.emergencyReadOnlyLockdown = false,
    this.enforce2FA = false,
    this.sessionTimeoutMinutes = 15,
    this.auditLogRetentionYears = 7,
    this.syncIntervalSeconds = 30,
    this.purgeTempCapturesAfterDays = 14,
    this.lastModified,
    this.modifiedBy,
  });

  String get rvgBridgeUrl => 'http://$rvgBridgeHost:$rvgBridgePort';

  factory PlatformSettingsModel.fromJson(Map<String, dynamic> json) {
    return PlatformSettingsModel(
      pacsAeTitle: json['pacsAeTitle'] as String? ?? 'CRUDOC_PACS',
      pacsPort: (json['pacsPort'] as num?)?.toInt() ?? 11112,
      enableCStoreAutoIngest: json['enableCStoreAutoIngest'] as bool? ?? true,
      dicomPreloadSliceCount:
          (json['dicomPreloadSliceCount'] as num?)?.toInt() ?? 16,
      highBitDepthRendering: json['highBitDepthRendering'] as bool? ?? true,
      progressiveStreaming: json['progressiveStreaming'] as bool? ?? true,
      defaultDoctorStorageQuotaGB:
          (json['defaultDoctorStorageQuotaGB'] as num?)?.toDouble() ?? 50.0,
      rvgBridgeHost: json['rvgBridgeHost'] as String? ?? '127.0.0.1',
      rvgBridgePort: (json['rvgBridgePort'] as num?)?.toInt() ?? 8766,
      rvgAcquisitionTimeoutSeconds:
          (json['rvgAcquisitionTimeoutSeconds'] as num?)?.toInt() ?? 45,
      allowSimulatedCaptureFallback:
          json['allowSimulatedCaptureFallback'] as bool? ?? true,
      autoDiscoverDrivers: json['autoDiscoverDrivers'] as bool? ?? true,
      defaultCalibrationProfile:
          json['defaultCalibrationProfile'] as String? ??
          'High Contrast Dental (16-bit)',
      odontogramNumberingSystem:
          json['odontogramNumberingSystem'] as String? ?? 'FDI (ISO 3950)',
      enablePediatricDentitionToggle:
          json['enablePediatricDentitionToggle'] as bool? ?? true,
      perioWarningDepthMm: (json['perioWarningDepthMm'] as num?)?.toInt() ?? 4,
      perioSevereDepthMm: (json['perioSevereDepthMm'] as num?)?.toInt() ?? 6,
      procedureCatalogVersion:
          json['procedureCatalogVersion'] as String? ?? 'CDT-2026.1',
      geminiModel: json['geminiModel'] as String? ?? 'gemini-2.5-flash',
      aiSecondReadConfidenceThreshold:
          (json['aiSecondReadConfidenceThreshold'] as num?)?.toDouble() ?? 0.85,
      ambientScribeAudioChunkSeconds:
          (json['ambientScribeAudioChunkSeconds'] as num?)?.toInt() ?? 30,
      autoSoapNotes: json['autoSoapNotes'] as bool? ?? true,
      redactPatientPii: json['redactPatientPii'] as bool? ?? true,
      maintenanceMode: json['maintenanceMode'] as bool? ?? false,
      maintenanceMessage:
          json['maintenanceMessage'] as String? ??
          'System maintenance in progress. Please save your work.',
      emergencyReadOnlyLockdown:
          json['emergencyReadOnlyLockdown'] as bool? ?? false,
      enforce2FA: json['enforce2FA'] as bool? ?? false,
      sessionTimeoutMinutes:
          (json['sessionTimeoutMinutes'] as num?)?.toInt() ?? 15,
      auditLogRetentionYears:
          (json['auditLogRetentionYears'] as num?)?.toInt() ?? 7,
      syncIntervalSeconds: (json['syncIntervalSeconds'] as num?)?.toInt() ?? 30,
      purgeTempCapturesAfterDays:
          (json['purgeTempCapturesAfterDays'] as num?)?.toInt() ?? 14,
      lastModified: (json['lastModified'] as Timestamp?)?.toDate(),
      modifiedBy: json['modifiedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pacsAeTitle': pacsAeTitle,
      'pacsPort': pacsPort,
      'enableCStoreAutoIngest': enableCStoreAutoIngest,
      'dicomPreloadSliceCount': dicomPreloadSliceCount,
      'highBitDepthRendering': highBitDepthRendering,
      'progressiveStreaming': progressiveStreaming,
      'defaultDoctorStorageQuotaGB': defaultDoctorStorageQuotaGB,
      'rvgBridgeHost': rvgBridgeHost,
      'rvgBridgePort': rvgBridgePort,
      'rvgAcquisitionTimeoutSeconds': rvgAcquisitionTimeoutSeconds,
      'allowSimulatedCaptureFallback': allowSimulatedCaptureFallback,
      'autoDiscoverDrivers': autoDiscoverDrivers,
      'defaultCalibrationProfile': defaultCalibrationProfile,
      'odontogramNumberingSystem': odontogramNumberingSystem,
      'enablePediatricDentitionToggle': enablePediatricDentitionToggle,
      'perioWarningDepthMm': perioWarningDepthMm,
      'perioSevereDepthMm': perioSevereDepthMm,
      'procedureCatalogVersion': procedureCatalogVersion,
      'geminiModel': geminiModel,
      'aiSecondReadConfidenceThreshold': aiSecondReadConfidenceThreshold,
      'ambientScribeAudioChunkSeconds': ambientScribeAudioChunkSeconds,
      'autoSoapNotes': autoSoapNotes,
      'redactPatientPii': redactPatientPii,
      'maintenanceMode': maintenanceMode,
      'maintenanceMessage': maintenanceMessage,
      'emergencyReadOnlyLockdown': emergencyReadOnlyLockdown,
      'enforce2FA': enforce2FA,
      'sessionTimeoutMinutes': sessionTimeoutMinutes,
      'auditLogRetentionYears': auditLogRetentionYears,
      'syncIntervalSeconds': syncIntervalSeconds,
      'purgeTempCapturesAfterDays': purgeTempCapturesAfterDays,
      'modifiedBy': modifiedBy,
    };
  }

  PlatformSettingsModel copyWith({
    String? pacsAeTitle,
    int? pacsPort,
    bool? enableCStoreAutoIngest,
    int? dicomPreloadSliceCount,
    bool? highBitDepthRendering,
    bool? progressiveStreaming,
    double? defaultDoctorStorageQuotaGB,
    String? rvgBridgeHost,
    int? rvgBridgePort,
    int? rvgAcquisitionTimeoutSeconds,
    bool? allowSimulatedCaptureFallback,
    bool? autoDiscoverDrivers,
    String? defaultCalibrationProfile,
    String? odontogramNumberingSystem,
    bool? enablePediatricDentitionToggle,
    int? perioWarningDepthMm,
    int? perioSevereDepthMm,
    String? procedureCatalogVersion,
    String? geminiModel,
    double? aiSecondReadConfidenceThreshold,
    int? ambientScribeAudioChunkSeconds,
    bool? autoSoapNotes,
    bool? redactPatientPii,
    bool? maintenanceMode,
    String? maintenanceMessage,
    bool? emergencyReadOnlyLockdown,
    bool? enforce2FA,
    int? sessionTimeoutMinutes,
    int? auditLogRetentionYears,
    int? syncIntervalSeconds,
    int? purgeTempCapturesAfterDays,
    DateTime? lastModified,
    String? modifiedBy,
  }) {
    return PlatformSettingsModel(
      pacsAeTitle: pacsAeTitle ?? this.pacsAeTitle,
      pacsPort: pacsPort ?? this.pacsPort,
      enableCStoreAutoIngest:
          enableCStoreAutoIngest ?? this.enableCStoreAutoIngest,
      dicomPreloadSliceCount:
          dicomPreloadSliceCount ?? this.dicomPreloadSliceCount,
      highBitDepthRendering:
          highBitDepthRendering ?? this.highBitDepthRendering,
      progressiveStreaming: progressiveStreaming ?? this.progressiveStreaming,
      defaultDoctorStorageQuotaGB:
          defaultDoctorStorageQuotaGB ?? this.defaultDoctorStorageQuotaGB,
      rvgBridgeHost: rvgBridgeHost ?? this.rvgBridgeHost,
      rvgBridgePort: rvgBridgePort ?? this.rvgBridgePort,
      rvgAcquisitionTimeoutSeconds:
          rvgAcquisitionTimeoutSeconds ?? this.rvgAcquisitionTimeoutSeconds,
      allowSimulatedCaptureFallback:
          allowSimulatedCaptureFallback ?? this.allowSimulatedCaptureFallback,
      autoDiscoverDrivers: autoDiscoverDrivers ?? this.autoDiscoverDrivers,
      defaultCalibrationProfile:
          defaultCalibrationProfile ?? this.defaultCalibrationProfile,
      odontogramNumberingSystem:
          odontogramNumberingSystem ?? this.odontogramNumberingSystem,
      enablePediatricDentitionToggle:
          enablePediatricDentitionToggle ?? this.enablePediatricDentitionToggle,
      perioWarningDepthMm: perioWarningDepthMm ?? this.perioWarningDepthMm,
      perioSevereDepthMm: perioSevereDepthMm ?? this.perioSevereDepthMm,
      procedureCatalogVersion:
          procedureCatalogVersion ?? this.procedureCatalogVersion,
      geminiModel: geminiModel ?? this.geminiModel,
      aiSecondReadConfidenceThreshold:
          aiSecondReadConfidenceThreshold ??
          this.aiSecondReadConfidenceThreshold,
      ambientScribeAudioChunkSeconds:
          ambientScribeAudioChunkSeconds ?? this.ambientScribeAudioChunkSeconds,
      autoSoapNotes: autoSoapNotes ?? this.autoSoapNotes,
      redactPatientPii: redactPatientPii ?? this.redactPatientPii,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      maintenanceMessage: maintenanceMessage ?? this.maintenanceMessage,
      emergencyReadOnlyLockdown:
          emergencyReadOnlyLockdown ?? this.emergencyReadOnlyLockdown,
      enforce2FA: enforce2FA ?? this.enforce2FA,
      sessionTimeoutMinutes:
          sessionTimeoutMinutes ?? this.sessionTimeoutMinutes,
      auditLogRetentionYears:
          auditLogRetentionYears ?? this.auditLogRetentionYears,
      syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
      purgeTempCapturesAfterDays:
          purgeTempCapturesAfterDays ?? this.purgeTempCapturesAfterDays,
      lastModified: lastModified ?? this.lastModified,
      modifiedBy: modifiedBy ?? this.modifiedBy,
    );
  }
}
