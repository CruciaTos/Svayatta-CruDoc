import 'package:flutter/material.dart';

/// Categories for clinical and communication campaigns.
enum CampaignCategory {
  healthAwareness,
  vaccinationDrive,
  checkupCamp,
  clinicUpdate,
  seasonalAdvisory,
  generalAnnouncement,
  followUp;

  String get label {
    switch (this) {
      case CampaignCategory.healthAwareness:
        return 'Health Awareness';
      case CampaignCategory.vaccinationDrive:
        return 'Vaccination Drive';
      case CampaignCategory.checkupCamp:
        return 'Health Checkup Camp';
      case CampaignCategory.clinicUpdate:
        return 'Clinic Update & Timing';
      case CampaignCategory.seasonalAdvisory:
        return 'Seasonal Advisory';
      case CampaignCategory.generalAnnouncement:
        return 'General Announcement';
      case CampaignCategory.followUp:
        return 'Follow-up & Care Plan';
    }
  }

  IconData get icon {
    switch (this) {
      case CampaignCategory.healthAwareness:
        return Icons.health_and_safety_rounded;
      case CampaignCategory.vaccinationDrive:
        return Icons.vaccines_rounded;
      case CampaignCategory.checkupCamp:
        return Icons.medical_services_rounded;
      case CampaignCategory.clinicUpdate:
        return Icons.access_time_filled_rounded;
      case CampaignCategory.seasonalAdvisory:
        return Icons.wb_sunny_rounded;
      case CampaignCategory.generalAnnouncement:
        return Icons.campaign_rounded;
      case CampaignCategory.followUp:
        return Icons.favorite_rounded;
    }
  }

  Color get color {
    switch (this) {
      case CampaignCategory.healthAwareness:
        return const Color(0xFF0284C7); // Sky Blue
      case CampaignCategory.vaccinationDrive:
        return const Color(0xFF059669); // Emerald Green
      case CampaignCategory.checkupCamp:
        return const Color(0xFF7C3AED); // Purple
      case CampaignCategory.clinicUpdate:
        return const Color(0xFFD97706); // Amber
      case CampaignCategory.seasonalAdvisory:
        return const Color(0xFFEA580C); // Orange
      case CampaignCategory.generalAnnouncement:
        return const Color(0xFF2563EB); // Royal Blue
      case CampaignCategory.followUp:
        return const Color(0xFFDB2777); // Pink
    }
  }

  static CampaignCategory fromString(String? val) {
    if (val == null) return CampaignCategory.generalAnnouncement;
    final clean = val.trim().toLowerCase();
    for (final cat in CampaignCategory.values) {
      if (cat.name.toLowerCase() == clean) return cat;
    }
    return CampaignCategory.generalAnnouncement;
  }
}

/// Overall lifecycle status of a campaign.
enum CampaignStatus {
  draft,
  scheduled,
  processing,
  completed,
  partiallyFailed,
  failed;

  String get label {
    switch (this) {
      case CampaignStatus.draft:
        return 'Draft';
      case CampaignStatus.scheduled:
        return 'Scheduled';
      case CampaignStatus.processing:
        return 'Sending...';
      case CampaignStatus.completed:
        return 'Completed';
      case CampaignStatus.partiallyFailed:
        return 'Partially Failed';
      case CampaignStatus.failed:
        return 'Failed';
    }
  }

  Color get color {
    switch (this) {
      case CampaignStatus.draft:
        return const Color(0xFF64748B);
      case CampaignStatus.scheduled:
        return const Color(0xFF0284C7);
      case CampaignStatus.processing:
        return const Color(0xFFD97706);
      case CampaignStatus.completed:
        return const Color(0xFF16A34A);
      case CampaignStatus.partiallyFailed:
        return const Color(0xFFEA580C);
      case CampaignStatus.failed:
        return const Color(0xFFDC2626);
    }
  }

  static CampaignStatus fromString(String? val) {
    if (val == null) return CampaignStatus.draft;
    final clean = val.trim().toLowerCase();
    for (final s in CampaignStatus.values) {
      if (s.name.toLowerCase() == clean) return s;
    }
    return CampaignStatus.draft;
  }
}

/// Communication channel selection.
enum CampaignChannel {
  email,
  whatsapp,
  both;

  String get label {
    switch (this) {
      case CampaignChannel.email:
        return 'Email Only';
      case CampaignChannel.whatsapp:
        return 'WhatsApp Only';
      case CampaignChannel.both:
        return 'Email & WhatsApp';
    }
  }

  bool get includesEmail => this == CampaignChannel.email || this == CampaignChannel.both;
  bool get includesWhatsApp => this == CampaignChannel.whatsapp || this == CampaignChannel.both;

  static CampaignChannel fromString(String? val) {
    if (val == null) return CampaignChannel.both;
    final clean = val.trim().toLowerCase();
    if (clean == 'email') return CampaignChannel.email;
    if (clean == 'whatsapp') return CampaignChannel.whatsapp;
    return CampaignChannel.both;
  }
}

/// Targeting cohort type for patients.
enum AudienceType {
  all,
  byDiagnosis,
  byGender,
  byAgeGroup,
  customSelection;

  String get label {
    switch (this) {
      case AudienceType.all:
        return 'All Active Patients';
      case AudienceType.byDiagnosis:
        return 'By Medical Condition';
      case AudienceType.byGender:
        return 'By Gender';
      case AudienceType.byAgeGroup:
        return 'By Age Group';
      case AudienceType.customSelection:
        return 'Specific Patients';
    }
  }

  static AudienceType fromString(String? val) {
    if (val == null) return AudienceType.all;
    final clean = val.trim().toLowerCase();
    for (final a in AudienceType.values) {
      if (a.name.toLowerCase() == clean) return a;
    }
    return AudienceType.all;
  }
}

/// Delivery status for individual recipient log.
enum RecipientDeliveryStatus {
  queued,
  sent,
  delivered,
  failed,
  skipped;

  String get label {
    switch (this) {
      case RecipientDeliveryStatus.queued:
        return 'Queued';
      case RecipientDeliveryStatus.sent:
        return 'Sent';
      case RecipientDeliveryStatus.delivered:
        return 'Delivered';
      case RecipientDeliveryStatus.failed:
        return 'Failed';
      case RecipientDeliveryStatus.skipped:
        return 'Skipped';
    }
  }

  Color get color {
    switch (this) {
      case RecipientDeliveryStatus.queued:
        return const Color(0xFF64748B);
      case RecipientDeliveryStatus.sent:
        return const Color(0xFF0284C7);
      case RecipientDeliveryStatus.delivered:
        return const Color(0xFF16A34A);
      case RecipientDeliveryStatus.failed:
        return const Color(0xFFDC2626);
      case RecipientDeliveryStatus.skipped:
        return const Color(0xFF94A3B8);
    }
  }

  static RecipientDeliveryStatus fromString(String? val) {
    if (val == null) return RecipientDeliveryStatus.queued;
    final clean = val.trim().toLowerCase();
    for (final s in RecipientDeliveryStatus.values) {
      if (s.name.toLowerCase() == clean) return s;
    }
    return RecipientDeliveryStatus.queued;
  }
}
