import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/repo/whatsapp_repository.dart';

/// Provider for the [WhatsAppRepository] singleton.
final whatsappRepositoryProvider = Provider<WhatsAppRepository>((ref) {
  return WhatsAppRepository();
});

/// Stream provider for real-time WhatsApp delivery status updates for a specific visit/appointment.
final visitWhatsAppStatusProvider =
    StreamProvider.autoDispose.family<WhatsAppNotificationLog?, String>((ref, visitId) {
  final repo = ref.watch(whatsappRepositoryProvider);
  return repo.watchVisitWhatsAppStatus(visitId);
});
