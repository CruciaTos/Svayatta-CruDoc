import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/messaging/data/providers/gmail_auth_providers.dart';
import '../repo/campaign_repository.dart';
import '../services/campaign_dispatch_service.dart';

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
