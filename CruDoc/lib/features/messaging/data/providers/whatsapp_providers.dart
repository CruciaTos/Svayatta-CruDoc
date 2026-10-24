import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_notification_log.dart';
import 'package:doctor_management_app/features/messaging/data/models/whatsapp_reply.dart';
import 'package:doctor_management_app/features/messaging/data/repo/whatsapp_repository.dart';

/// Provider for the [WhatsAppRepository] singleton.
final whatsappRepositoryProvider = Provider<WhatsAppRepository>((ref) {
  return WhatsAppRepository();
});

/// Stream provider for real-time WhatsApp delivery status updates for a specific visit/appointment.
final visitWhatsAppStatusProvider = StreamProvider.autoDispose
    .family<WhatsAppNotificationLog?, String>((ref, visitId) {
      final repo = ref.watch(whatsappRepositoryProvider);
      return repo.watchVisitWhatsAppStatus(visitId);
    });

/// Reminders that failed to send (Notifications).
final failedRemindersProvider = StreamProvider<List<WhatsAppNotificationLog>>(
  (ref) {
    ref.watch(authStateProvider);
    return ref.watch(whatsappRepositoryProvider).watchFailedLogs();
  },
);

/// Patients' replies to the reminder number (Notifications).
final whatsAppRepliesProvider = StreamProvider<List<WhatsAppReply>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(whatsappRepositoryProvider).watchRecentReplies();
});
