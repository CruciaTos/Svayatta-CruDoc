import 'package:intl/intl.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Formatted subject and body content for an appointment email.
class AppointmentEmailContent {
  final String subject;
  final String body;

  const AppointmentEmailContent({
    required this.subject,
    required this.body,
  });
}

/// Helper service that generates clean, professional plain-text appointment confirmation emails.
class AppointmentEmailTemplate {
  /// Builds an appointment booking confirmation email content.
  static AppointmentEmailContent buildConfirmation({
    required Visit visit,
    required Patient patient,
    required String doctorName,
    String specialty = 'Medical Practitioner',
    String? clinicName,
    String? clinicAddress,
  }) {
    final dateFormat = DateFormat('EEEE, d MMMM yyyy');
    final timeFormat = DateFormat('h:mm a');

    final formattedDate = dateFormat.format(visit.scheduledStart);
    final formattedStartTime = timeFormat.format(visit.scheduledStart);
    final formattedEndTime = timeFormat.format(visit.scheduledEnd);

    final patientName = patient.fullName.trim().isNotEmpty
        ? patient.fullName.trim()
        : 'Patient';

    final isHomeVisit = visit.visitType == VisitType.home;
    final visitTypeLabel = isHomeVisit ? 'Home Visit Consultation' : 'In-Clinic Consultation';

    String location = 'Clinic';
    if (isHomeVisit) {
      location = visit.address.trim().isNotEmpty
          ? visit.address.trim()
          : 'Patient Home Address';
    } else {
      if (visit.address.trim().isNotEmpty) {
        location = visit.address.trim();
      } else if (clinicAddress != null && clinicAddress.trim().isNotEmpty) {
        location = clinicAddress.trim();
      } else {
        location = clinicName != null && clinicName.trim().isNotEmpty
            ? clinicName.trim()
            : 'Doctor Clinic';
      }
    }

    final subject = 'Appointment Confirmation: $doctorName on $formattedDate';

    final body = '''
Dear $patientName,

Your appointment with $doctorName ($specialty) has been successfully scheduled.

APPOINTMENT DETAILS:
--------------------------------------------------
• Date: $formattedDate
• Time: $formattedStartTime - $formattedEndTime (${visit.durationMinutes} mins)
• Type: $visitTypeLabel
• Location: $location
--------------------------------------------------

If you need to reschedule or have any questions prior to your consultation, please get in touch with us.

Thank you,
$doctorName
CruDoc Healthcare Management
''';

    return AppointmentEmailContent(subject: subject, body: body.trim());
  }
}
