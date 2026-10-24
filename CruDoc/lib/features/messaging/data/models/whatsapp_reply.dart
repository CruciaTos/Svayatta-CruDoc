import 'package:cloud_firestore/cloud_firestore.dart';

/// A message a patient sent back to the reminder number. The server writes
/// these (collection `whatsapp_replies`); the app only reads them.
class WhatsAppReply {
  const WhatsAppReply({
    required this.id,
    required this.patientId,
    required this.name,
    required this.phone,
    required this.kind,
    required this.text,
    required this.receivedAt,
  });

  final String id;
  final String patientId;
  final String name;
  final String phone;

  /// 'text', 'stop' (turned reminders off) or 'start' (turned them on).
  final String kind;
  final String text;
  final DateTime receivedAt;

  factory WhatsAppReply.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final at = d['receivedAt'];
    return WhatsAppReply(
      id: doc.id,
      patientId: d['patientId'] as String? ?? '',
      name: d['name'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      kind: d['kind'] as String? ?? 'text',
      text: d['text'] as String? ?? '',
      receivedAt: at is Timestamp ? at.toDate() : DateTime.now(),
    );
  }
}
