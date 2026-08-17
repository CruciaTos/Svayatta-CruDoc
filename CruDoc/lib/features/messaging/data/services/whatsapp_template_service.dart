import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Utilities for WhatsApp phone number normalization, message templating,
/// and deep linking, strictly adhering to medical privacy standards.
class WhatsAppTemplateService {
  WhatsAppTemplateService._();

  /// Normalizes a raw phone string into a clean E.164 compatible string without '+' or symbols.
  /// Defaults to India '91' for 10-digit mobile numbers.
  ///
  /// Examples:
  /// - `+91 98765-43210` -> `919876543210`
  /// - `9876543210`      -> `919876543210`
  /// - `09876543210`     -> `919876543210`
  /// - `+1 (555) 234-5678` -> `15552345678`
  static String? normalizePhone(String? raw, {String defaultCountryCode = '91'}) {
    if (raw == null || raw.trim().isEmpty) return null;

    // Strip non-digits
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    // Strip leading zeros
    digits = digits.replaceFirst(RegExp(r'^0+'), '');

    // 10-digit number -> prepend default country code
    if (digits.length == 10) {
      digits = '$defaultCountryCode$digits';
    }

    // E.164 length validation (10 to 15 digits)
    if (digits.length < 10 || digits.length > 15) {
      return null;
    }

    return digits;
  }

  /// Checks if a raw phone string resolves to a valid WhatsApp recipient.
  static bool isValidWhatsAppPhone(String? raw) {
    return normalizePhone(raw) != null;
  }

  /// Formats a phone number for user-friendly UI display (e.g. `+91 98765 43210`).
  static String formatDisplayPhone(String? raw) {
    final normalized = normalizePhone(raw);
    if (normalized == null) return raw ?? '';

    if (normalized.startsWith('91') && normalized.length == 12) {
      final sub = normalized.substring(2);
      return '+91 ${sub.substring(0, 5)} ${sub.substring(5)}';
    }
    return '+$normalized';
  }

  /// Formats date into readable string: `Monday, Aug 18, 2026`
  static String formatDate(DateTime dateTime) {
    return DateFormat('EEE, MMM d, yyyy').format(dateTime);
  }

  /// Formats time into readable string: `10:30 AM`
  static String formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  /// Formats visit consultation type.
  static String formatConsultationType(VisitType type) {
    return type == VisitType.home ? 'Home Visit Consultation' : 'In-Clinic Consultation';
  }

  /// Builds a standard, privacy-compliant WhatsApp confirmation message.
  ///
  /// STRICT PRIVACY GUARDRAILS:
  /// - Only contains operational details (Doctor, Patient Name, Clinic, Date, Time, Location Type).
  /// - Strictly excludes medical diagnoses, prescriptions, and therapist notes.
  static String buildConfirmationMessage({
    required Visit visit,
    required Patient patient,
    required String doctorName,
    String? clinicName,
  }) {
    final effectiveClinic = (clinicName != null && clinicName.trim().isNotEmpty)
        ? clinicName.trim()
        : 'CruDoc Practice';

    final effectiveDoctor = doctorName.trim().isNotEmpty ? doctorName.trim() : 'Doctor';
    final patientName = patient.fullName.trim().isNotEmpty ? patient.fullName.trim() : 'Valued Patient';

    final dateStr = formatDate(visit.scheduledStart);
    final timeStr = formatTime(visit.scheduledStart);
    final typeStr = formatConsultationType(visit.visitType);

    final buffer = StringBuffer();
    buffer.writeln('🏥 *Appointment Confirmation*');
    buffer.writeln();
    buffer.writeln('Hello *$patientName*,');
    buffer.writeln('Your appointment with *$effectiveDoctor* at *$effectiveClinic* is confirmed.');
    buffer.writeln();
    buffer.writeln('📅 *Date:* $dateStr');
    buffer.writeln('⏰ *Time:* $timeStr');
    buffer.writeln('📍 *Type:* $typeStr');

    if (visit.address.trim().isNotEmpty && visit.visitType == VisitType.home) {
      buffer.writeln('🏠 *Address:* ${visit.address.trim()}');
    }

    buffer.writeln();
    buffer.writeln('If you need to reschedule or have any questions, please reply to this message. Thank you!');

    return buffer.toString();
  }

  /// Builds a `https://wa.me/<phone>?text=<encodedMessage>` URL for 1-click direct sending in WhatsApp.
  static Uri? buildDirectWhatsAppUrl({
    required String? rawPhone,
    required String message,
  }) {
    final phone = normalizePhone(rawPhone);
    if (phone == null) return null;

    return Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  }
}
