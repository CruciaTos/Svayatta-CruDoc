import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repo/campaign_repository.dart';
import '../services/campaign_dispatch_service.dart';

/// Shared [CampaignRepository] instance for the campaigns feature.
final campaignRepositoryProvider = Provider<CampaignRepository>((ref) {
  return CampaignRepository();
});

/// Shared [CampaignDispatchService], wired to the same repository instance so
/// dispatch writes and campaign reads go through one source of truth.
final campaignDispatchServiceProvider = Provider<CampaignDispatchService>((
  ref,
) {
  return CampaignDispatchService(
    campaignRepository: ref.watch(campaignRepositoryProvider),
  );
});
