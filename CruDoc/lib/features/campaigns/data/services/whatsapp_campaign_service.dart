import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Client access to the per-clinic WhatsApp campaign backend.
///
/// WhatsApp campaigns are never sent from the client: it reads whether the
/// clinic's own number is connected (a server-written mirror) and hands a
/// campaign to the `enqueueCampaign` callable, which queues it on the outbox
/// and sends it server-side as the clinic. See functions/src/whatsapp-outbox.ts.
class WhatsAppCampaignService {
  WhatsAppCampaignService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  static const _connectionsCollection = 'whatsapp_connections';

  /// Live connection status for a clinic's own WhatsApp number.
  ///
  /// Emits null when the clinic has never connected a number.
  Stream<WhatsAppConnection?> watchConnection(String doctorId) {
    return _firestore
        .collection(_connectionsCollection)
        .doc(doctorId)
        .snapshots()
        .map(
          (snap) => snap.exists && snap.data() != null
              ? WhatsAppConnection.fromMap(snap.data()!)
              : null,
        );
  }

  /// Queues a WhatsApp campaign for server-side sending.
  ///
  /// Throws [FirebaseFunctionsException] — notably `failed-precondition` when
  /// the clinic's number is not connected — which the caller surfaces.
  Future<WhatsAppEnqueueResult> enqueueCampaign({
    required String campaignId,
    required String message,
    required String clinicName,
    required String clinicPhone,
    required List<WhatsAppCampaignRecipient> recipients,
  }) async {
    final callable = _functions.httpsCallable('enqueueCampaign');
    final res = await callable.call<Map<String, dynamic>>({
      'campaignId': campaignId,
      'message': message,
      'clinicName': clinicName,
      'clinicPhone': clinicPhone,
      'recipients': [for (final r in recipients) r.toMap()],
    });
    return WhatsAppEnqueueResult.fromMap(
      Map<String, dynamic>.from(res.data),
    );
  }
}

/// One campaign recipient as the callable expects it.
class WhatsAppCampaignRecipient {
  const WhatsAppCampaignRecipient({
    required this.phone,
    required this.firstName,
    this.patientId,
  });

  final String? patientId;
  final String phone;
  final String firstName;

  factory WhatsAppCampaignRecipient.fromPatient(Patient p) =>
      WhatsAppCampaignRecipient(
        patientId: p.id,
        phone: p.phone,
        firstName: p.firstName,
      );

  Map<String, dynamic> toMap() => {
    'patientId': patientId,
    'phone': phone,
    'firstName': firstName,
  };
}

/// The clinic's WhatsApp connection, mirrored from the server.
class WhatsAppConnection {
  const WhatsAppConnection({
    required this.connected,
    required this.status,
    this.displayPhoneNumber,
    this.verifiedName,
    this.needsReauth = false,
  });

  final bool connected;

  /// connected | reauth_required | disconnected | pending_register
  final String status;
  final String? displayPhoneNumber;
  final String? verifiedName;
  final bool needsReauth;

  bool get canSend => connected && !needsReauth;

  factory WhatsAppConnection.fromMap(Map<String, dynamic> map) {
    return WhatsAppConnection(
      connected: map['connected'] as bool? ?? false,
      status: map['status'] as String? ?? 'disconnected',
      displayPhoneNumber: map['displayPhoneNumber'] as String?,
      verifiedName: map['verifiedName'] as String?,
      needsReauth: map['needsReauth'] as bool? ?? false,
    );
  }
}

/// The result the `enqueueCampaign` callable returns.
class WhatsAppEnqueueResult {
  const WhatsAppEnqueueResult({
    required this.queued,
    required this.alreadyQueued,
    required this.skipped,
  });

  /// Newly queued messages.
  final int queued;

  /// Messages a prior call already queued (idempotent re-send).
  final int alreadyQueued;

  /// Skip reason → count (invalid_or_missing_phone, no_patient_name,
  /// opted_out, duplicate).
  final Map<String, int> skipped;

  int get totalSkipped => skipped.values.fold(0, (s, n) => s + n);

  factory WhatsAppEnqueueResult.fromMap(Map<String, dynamic> map) {
    final rawSkipped = map['skipped'];
    final skipped = <String, int>{};
    if (rawSkipped is Map) {
      rawSkipped.forEach((key, value) {
        skipped['$key'] = (value as num?)?.toInt() ?? 0;
      });
    }
    return WhatsAppEnqueueResult(
      queued: (map['queued'] as num?)?.toInt() ?? 0,
      alreadyQueued: (map['alreadyQueued'] as num?)?.toInt() ?? 0,
      skipped: skipped,
    );
  }
}
