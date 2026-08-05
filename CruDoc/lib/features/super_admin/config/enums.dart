// Enums used across the Super Admin module.

/// Status of a doctor account
enum DoctorStatus {
  active,
  suspended,
  trial,
  expired,
  pending;

  String get label {
    switch (this) {
      case DoctorStatus.active:
        return 'Active';
      case DoctorStatus.suspended:
        return 'Suspended';
      case DoctorStatus.trial:
        return 'Trial';
      case DoctorStatus.expired:
        return 'Expired';
      case DoctorStatus.pending:
        return 'Pending';
    }
  }
}

/// Subscription plan levels
enum SubscriptionPlan {
  starter,
  professional,
  clinic,
  enterprise;

  String get label {
    switch (this) {
      case SubscriptionPlan.starter:
        return 'Starter';
      case SubscriptionPlan.professional:
        return 'Professional';
      case SubscriptionPlan.clinic:
        return 'Clinic';
      case SubscriptionPlan.enterprise:
        return 'Enterprise';
    }
  }

  double get monthlyPrice {
    switch (this) {
      case SubscriptionPlan.starter:
        return 29.0;
      case SubscriptionPlan.professional:
        return 79.0;
      case SubscriptionPlan.clinic:
        return 199.0;
      case SubscriptionPlan.enterprise:
        return 499.0;
    }
  }

  double get annualPrice => monthlyPrice * 10; // 2 months free

  double get storageLimitGB {
    switch (this) {
      case SubscriptionPlan.starter:
        return 5.0;
      case SubscriptionPlan.professional:
        return 20.0;
      case SubscriptionPlan.clinic:
        return 50.0;
      case SubscriptionPlan.enterprise:
        return 200.0;
    }
  }

  int get patientLimit {
    switch (this) {
      case SubscriptionPlan.starter:
        return 200;
      case SubscriptionPlan.professional:
        return 1000;
      case SubscriptionPlan.clinic:
        return 5000;
      case SubscriptionPlan.enterprise:
        return -1; // unlimited
    }
  }

  int get staffSlots {
    switch (this) {
      case SubscriptionPlan.starter:
        return 1;
      case SubscriptionPlan.professional:
        return 3;
      case SubscriptionPlan.clinic:
        return 10;
      case SubscriptionPlan.enterprise:
        return 50;
    }
  }

  int get ocrLimitPerMonth {
    switch (this) {
      case SubscriptionPlan.starter:
        return 100;
      case SubscriptionPlan.professional:
        return 500;
      case SubscriptionPlan.clinic:
        return 2000;
      case SubscriptionPlan.enterprise:
        return 10000;
    }
  }

  int get appointmentLimitPerMonth {
    switch (this) {
      case SubscriptionPlan.starter:
        return 100;
      case SubscriptionPlan.professional:
        return 500;
      case SubscriptionPlan.clinic:
        return 2000;
      case SubscriptionPlan.enterprise:
        return -1; // unlimited
    }
  }

  int get onlineSessionsPerMonth {
    switch (this) {
      case SubscriptionPlan.starter:
        return 0;
      case SubscriptionPlan.professional:
        return 50;
      case SubscriptionPlan.clinic:
        return 200;
      case SubscriptionPlan.enterprise:
        return 1000;
    }
  }

  bool get customDomain => this == SubscriptionPlan.enterprise;
  bool get whiteLabel => this == SubscriptionPlan.enterprise;

  List<String> get includedModules {
    final base = <String>[
      'dashboard',
      'patients',
      'appointments',
      'inventory',
      'reports',
    ];
    switch (this) {
      case SubscriptionPlan.starter:
        return base;
      case SubscriptionPlan.professional:
        return [...base, 'revenue', 'analytics', 'session_history'];
      case SubscriptionPlan.clinic:
        return [
          ...base,
          'revenue',
          'analytics',
          'session_history',
          'home_visits',
          'medicine_ocr',
          'prescription_generator',
          'packages',
        ];
      case SubscriptionPlan.enterprise:
        return [
          ...base,
          'revenue',
          'analytics',
          'session_history',
          'home_visits',
          'medicine_ocr',
          'medicine_bills',
          'prescription_generator',
          'packages',
          'online_consultation',
          'whatsapp_integration',
          'ai_assistant',
          'custom_branding',
        ];
    }
  }
}

/// Priority level for support tickets
enum TicketPriority {
  low,
  medium,
  high,
  critical;

  String get label {
    switch (this) {
      case TicketPriority.low:
        return 'Low';
      case TicketPriority.medium:
        return 'Medium';
      case TicketPriority.high:
        return 'High';
      case TicketPriority.critical:
        return 'Critical';
    }
  }
}

/// Status of a support ticket
enum TicketStatus {
  open,
  inProgress,
  resolved,
  closed;

  String get label {
    switch (this) {
      case TicketStatus.open:
        return 'Open';
      case TicketStatus.inProgress:
        return 'In Progress';
      case TicketStatus.resolved:
        return 'Resolved';
      case TicketStatus.closed:
        return 'Closed';
    }
  }
}

/// Category of a support ticket
enum TicketCategory {
  bug,
  complaint,
  feedback,
  suggestion,
  featureRequest;

  String get label {
    switch (this) {
      case TicketCategory.bug:
        return 'Bug';
      case TicketCategory.complaint:
        return 'Complaint';
      case TicketCategory.feedback:
        return 'Feedback';
      case TicketCategory.suggestion:
        return 'Suggestion';
      case TicketCategory.featureRequest:
        return 'Feature Request';
    }
  }
}

/// Type of admin action for audit logs
enum AuditActionType {
  createdDoctor,
  updatedDoctor,
  deletedDoctor,
  resetPassword,
  changedPlan,
  enabledModule,
  disabledModule,
  suspendedAccount,
  activatedAccount,
  extendedTrial,
  editedPlanDefinition,
  sentAnnouncement,
  updatedSystemConfig,
  assignedSupportTicket,
  resolvedSupportTicket;

  String get label {
    switch (this) {
      case AuditActionType.createdDoctor:
        return 'Created Doctor';
      case AuditActionType.updatedDoctor:
        return 'Updated Doctor';
      case AuditActionType.deletedDoctor:
        return 'Deleted Doctor';
      case AuditActionType.resetPassword:
        return 'Reset Password';
      case AuditActionType.changedPlan:
        return 'Changed Plan';
      case AuditActionType.enabledModule:
        return 'Enabled Module';
      case AuditActionType.disabledModule:
        return 'Disabled Module';
      case AuditActionType.suspendedAccount:
        return 'Suspended Account';
      case AuditActionType.activatedAccount:
        return 'Activated Account';
      case AuditActionType.extendedTrial:
        return 'Extended Trial';
      case AuditActionType.editedPlanDefinition:
        return 'Edited Plan Definition';
      case AuditActionType.sentAnnouncement:
        return 'Sent Announcement';
      case AuditActionType.updatedSystemConfig:
        return 'Updated System Config';
      case AuditActionType.assignedSupportTicket:
        return 'Assigned Support Ticket';
      case AuditActionType.resolvedSupportTicket:
        return 'Resolved Support Ticket';
    }
  }
}

/// Enabled feature modules
enum FeatureModule {
  dashboard,
  patients,
  sessionHistory,
  appointments,
  homeVisits,
  revenue,
  inventory,
  medicineOcr,
  medicineBills,
  prescriptionGenerator,
  packages,
  reports,
  analytics,
  onlineConsultation,
  whatsappIntegration,
  aiAssistant,
  customBranding;

  String get label {
    switch (this) {
      case FeatureModule.dashboard:
        return 'Dashboard';
      case FeatureModule.patients:
        return 'Patients';
      case FeatureModule.sessionHistory:
        return 'Session History';
      case FeatureModule.appointments:
        return 'Appointments';
      case FeatureModule.homeVisits:
        return 'Home Visits';
      case FeatureModule.revenue:
        return 'Revenue';
      case FeatureModule.inventory:
        return 'Inventory';
      case FeatureModule.medicineOcr:
        return 'Medicine OCR';
      case FeatureModule.medicineBills:
        return 'Medicine Bills';
      case FeatureModule.prescriptionGenerator:
        return 'Prescription Generator';
      case FeatureModule.packages:
        return 'Packages';
      case FeatureModule.reports:
        return 'Reports';
      case FeatureModule.analytics:
        return 'Analytics';
      case FeatureModule.onlineConsultation:
        return 'Online Consultation';
      case FeatureModule.whatsappIntegration:
        return 'WhatsApp Integration';
      case FeatureModule.aiAssistant:
        return 'AI Assistant';
      case FeatureModule.customBranding:
        return 'Custom Branding';
    }
  }
}

/// User roles in the system
enum UserRole {
  superAdmin,
  clinicOwner,
  doctor,
  receptionist,
  assistant;

  String get label {
    switch (this) {
      case UserRole.superAdmin:
        return 'Super Admin';
      case UserRole.clinicOwner:
        return 'Clinic Owner';
      case UserRole.doctor:
        return 'Doctor';
      case UserRole.receptionist:
        return 'Receptionist';
      case UserRole.assistant:
        return 'Assistant';
    }
  }
}

/// Platform health status
enum PlatformHealth {
  healthy,
  warning,
  critical;

  String get label {
    switch (this) {
      case PlatformHealth.healthy:
        return 'Healthy';
      case PlatformHealth.warning:
        return 'Warning';
      case PlatformHealth.critical:
        return 'Critical';
    }
  }
}