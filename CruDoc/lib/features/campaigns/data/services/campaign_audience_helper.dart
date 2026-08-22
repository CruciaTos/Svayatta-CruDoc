import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import '../models/campaign_enums.dart';

/// Helper for filtering patient cohorts, interpolating template tokens,
/// and building sanitized dual-channel message payloads.
class CampaignAudienceHelper {
  // Strict email regex matching RFC 5322
  static final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  /// Validates whether an email string is well-formed.
  static bool isValidEmail(String email) {
    final clean = email.trim();
    if (clean.isEmpty || clean.length > 254) return false;
    return _emailRegex.hasMatch(clean);
  }

  /// Filters patients according to targeting rules.
  static List<Patient> filterPatients({
    required List<Patient> allPatients,
    required AudienceType audienceType,
    Map<String, dynamic> filters = const {},
    List<String> selectedPatientIds = const [],
  }) {
    // 1. Filter out archived records
    final activePatients = allPatients.where((p) => !p.isArchived).toList();

    switch (audienceType) {
      case AudienceType.all:
        return activePatients;

      case AudienceType.byDiagnosis:
        final targetCondition =
            (filters['condition'] ?? filters['diagnosis'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        if (targetCondition.isEmpty) return activePatients;

        return activePatients.where((p) {
          if (p.diagnosis.isEmpty) return false;
          return p.diagnosis.any(
              (d) => d.toLowerCase().contains(targetCondition));
        }).toList();

      case AudienceType.byGender:
        final targetGender =
            (filters['gender'] ?? '').toString().trim().toLowerCase();
        if (targetGender.isEmpty || targetGender == 'all') return activePatients;

        return activePatients.where((p) {
          return p.gender.trim().toLowerCase() == targetGender;
        }).toList();

      case AudienceType.byAgeGroup:
        final minAge = (filters['minAge'] as num?)?.toInt() ?? 0;
        final maxAge = (filters['maxAge'] as num?)?.toInt() ?? 150;

        return activePatients.where((p) {
          final age = p.age;
          return age >= minAge && age <= maxAge;
        }).toList();

      case AudienceType.customSelection:
        if (selectedPatientIds.isEmpty) return [];
        final idSet = selectedPatientIds.toSet();
        return activePatients.where((p) => idSet.contains(p.id)).toList();
    }
  }

  /// Replaces dynamic placeholders (`{{patient_name}}`, `{{clinic_name}}`, `{{doctor_name}}`)
  /// with actual patient and clinic details.
  static String interpolateVariables(
    String template, {
    required Patient patient,
    String? doctorName,
    String? clinicName,
  }) {
    var result = template;
    final pName = patient.fullName.trim().isNotEmpty
        ? patient.fullName.trim()
        : (patient.firstName.isNotEmpty ? patient.firstName : 'Valued Patient');

    final dName = (doctorName != null && doctorName.trim().isNotEmpty)
        ? doctorName.trim()
        : 'Your Healthcare Provider';

    final cName = (clinicName != null && clinicName.trim().isNotEmpty)
        ? clinicName.trim()
        : 'Our Clinic';

    // Replace variations of placeholders
    result = result
        .replaceAll(RegExp(r'\{\{\s*patient_name\s*\}\}', caseSensitive: false), pName)
        .replaceAll(RegExp(r'\{\{\s*name\s*\}\}', caseSensitive: false), pName)
        .replaceAll(RegExp(r'\{\{\s*first_name\s*\}\}', caseSensitive: false),
            patient.firstName.isNotEmpty ? patient.firstName : pName)
        .replaceAll(RegExp(r'\{\{\s*doctor_name\s*\}\}', caseSensitive: false), dName)
        .replaceAll(RegExp(r'\{\{\s*clinic_name\s*\}\}', caseSensitive: false), cName)
        .replaceAll(RegExp(r'\{\{\s*phone\s*\}\}', caseSensitive: false), patient.phone);

    return result;
  }

  /// Formats the email subject line cleanly.
  static String buildEmailSubject(String title, {String? clinicName}) {
    final cleanTitle = title.trim();
    if (clinicName != null && clinicName.trim().isNotEmpty) {
      return '$cleanTitle | ${clinicName.trim()}';
    }
    return cleanTitle;
  }

  /// Builds a responsive, branded HTML email message body.
  static String buildFormattedEmailHtml(
    String rawMessage, {
    required String title,
    required Patient patient,
    CampaignCategory category = CampaignCategory.generalAnnouncement,
    String? clinicName,
    String? doctorName,
    String? mediaUrl,
  }) {
    final interpolatedBody = interpolateVariables(
      rawMessage,
      patient: patient,
      doctorName: doctorName,
      clinicName: clinicName,
    );

    // Convert line breaks to HTML paragraphs
    final paragraphs = interpolatedBody
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((p) => '<p style="margin: 0 0 16px 0; font-size: 15px; line-height: 1.6; color: #334155;">$p</p>')
        .join('');

    final cName = clinicName?.trim().isNotEmpty == true ? clinicName!.trim() : 'Healthcare Centre';
    final dName = doctorName?.trim().isNotEmpty == true ? doctorName!.trim() : 'Your Healthcare Provider';
    final badgeColorHex = '#${category.color.value.toRadixString(16).substring(2)}';

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <table width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color: #f8fafc; padding: 32px 16px;">
    <tr>
      <td align="center">
        <table width="600" border="0" cellspacing="0" cellpadding="0" style="max-width: 600px; width: 100%; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.06); border: 1px solid #e2e8f0;">
          
          <!-- Clinic Header -->
          <tr>
            <td style="padding: 28px 32px; background: linear-gradient(135deg, #1e293b, #0f172a); color: #ffffff;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td>
                    <div style="font-size: 18px; font-weight: 700; letter-spacing: -0.3px;">$cName</div>
                    <div style="font-size: 12px; color: #94a3b8; margin-top: 2px;">Patient Care & Health Advisory</div>
                  </td>
                  <td align="right">
                    <span style="display: inline-block; padding: 4px 12px; background-color: rgba(255,255,255,0.15); border-radius: 20px; font-size: 11px; font-weight: 600; color: #ffffff; letter-spacing: 0.5px;">${category.label.toUpperCase()}</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Banner Image if provided -->
          ${mediaUrl != null && mediaUrl.isNotEmpty ? '''
          <tr>
            <td>
              <img src="$mediaUrl" alt="$title" style="width: 100%; max-height: 240px; object-fit: cover; display: block;" />
            </td>
          </tr>
          ''' : ''}

          <!-- Main Content -->
          <tr>
            <td style="padding: 32px;">
              <h1 style="margin: 0 0 20px 0; font-size: 22px; font-weight: 700; color: #0f172a; line-height: 1.3;">$title</h1>
              
              $paragraphs

              <!-- Doctor Signature Card -->
              <div style="margin-top: 32px; padding: 16px 20px; background-color: #f1f5f9; border-radius: 12px; border-left: 4px solid $badgeColorHex;">
                <div style="font-size: 14px; font-weight: 700; color: #0f172a;">$dName</div>
                <div style="font-size: 12px; color: #64748b; margin-top: 2px;">$cName</div>
              </div>
            </td>
          </tr>

          <!-- Footer & Opt-Out -->
          <tr>
            <td style="padding: 24px 32px; background-color: #f8fafc; border-top: 1px solid #e2e8f0; text-align: center; font-size: 12px; color: #94a3b8; line-height: 1.5;">
              <p style="margin: 0 0 6px 0;">This official health communication was sent to <strong>${patient.fullName}</strong> by $cName.</p>
              <p style="margin: 0;">To update your notification preferences, please contact our clinic reception.</p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';
  }

  /// Builds a clean, emoji-formatted WhatsApp message body.
  static String buildFormattedWhatsAppText(
    String rawMessage, {
    required String title,
    required Patient patient,
    CampaignCategory category = CampaignCategory.generalAnnouncement,
    String? clinicName,
    String? doctorName,
  }) {
    final interpolatedBody = interpolateVariables(
      rawMessage,
      patient: patient,
      doctorName: doctorName,
      clinicName: clinicName,
    );

    final cName = clinicName?.trim().isNotEmpty == true ? clinicName!.trim() : 'Clinic';
    final dName = doctorName?.trim().isNotEmpty == true ? doctorName!.trim() : 'Your Doctor';

    final categoryEmoji = _getCategoryEmoji(category);

    return '''
$categoryEmoji *${title.trim()}*
_${cName}_

$interpolatedBody

───────────────
👨‍⚕️ *$dName*
🏥 $cName
📞 Reply to this message for appointment bookings or inquiries.
'''.trim();
  }

  /// Builds a clean, emoji-formatted WhatsApp message body with optional media attachment.
  static String buildFormattedWhatsAppMessage(
    String rawMessage, {
    required String title,
    required Patient patient,
    CampaignCategory category = CampaignCategory.generalAnnouncement,
    String? clinicName,
    String? doctorName,
    String? mediaUrl,
  }) {
    final text = buildFormattedWhatsAppText(
      rawMessage,
      title: title,
      patient: patient,
      category: category,
      clinicName: clinicName,
      doctorName: doctorName,
    );
    if (mediaUrl != null && mediaUrl.trim().isNotEmpty) {
      return '$text\n\n🖼️ View Image: ${mediaUrl.trim()}';
    }
    return text;
  }

  static String _getCategoryEmoji(CampaignCategory category) {
    switch (category) {
      case CampaignCategory.healthAwareness:
        return '🩺';
      case CampaignCategory.vaccinationDrive:
        return '💉';
      case CampaignCategory.checkupCamp:
        return '🏥';
      case CampaignCategory.clinicUpdate:
        return '⏰';
      case CampaignCategory.seasonalAdvisory:
        return '☀️';
      case CampaignCategory.generalAnnouncement:
        return '📢';
      case CampaignCategory.followUp:
        return '💙';
    }
  }
}
