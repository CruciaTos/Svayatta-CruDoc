import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/messaging/data/providers/gmail_auth_providers.dart';
import '../repo/campaign_repository.dart';
import '../services/campaign_dispatch_service.dart';
import '../services/whatsapp_campaign_service.dart';

/// Shared [CampaignRepository] instance for the campaigns feature.
final campaignRepositoryProvider = Provider<CampaignRepository>((ref) {
  return CampaignRepository();
});

/// Shared [CampaignDispatchService], wired to the same repository instance so
/// dispatch writes and campaign reads go through one source of truth, and to
/// the shared Gmail auth singleton so a Gmail account connected anywhere in the
/// app (e.g. Profile) is seen here too.
final campaignDispatchServiceProvider = Provider<CampaignDispatchService>((
  ref,
) {
  return CampaignDispatchService(
    campaignRepository: ref.watch(campaignRepositoryProvider),
    gmailAuthService: ref.watch(gmailAuthServiceProvider),
  );
});

/// Client access to the per-clinic WhatsApp campaign backend.
final whatsAppCampaignServiceProvider = Provider<WhatsAppCampaignService>((
  ref,
) {
  return WhatsAppCampaignService();
});

/// Live connection status for the current doctor's own WhatsApp number.
///
/// Emits null when nothing is connected (the expected state until a clinic
/// completes WhatsApp onboarding), which gates the WhatsApp campaign channel.
final whatsAppConnectionProvider =
    StreamProvider.autoDispose<WhatsAppConnection?>((ref) {
      final doctorId = FirebaseAuth.instance.currentUser?.uid;
      if (doctorId == null || doctorId.isEmpty) {
        return const Stream<WhatsAppConnection?>.empty();
      }
      return ref
          .watch(whatsAppCampaignServiceProvider)
          .watchConnection(doctorId);
    });
