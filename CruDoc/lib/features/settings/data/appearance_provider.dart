import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/theme/cru_colors.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/settings/data/appearance_preferences.dart';

final appearancePreferencesProvider = Provider<AppearancePreferences>(
  (ref) => AppearancePreferences(),
);

/// Auto / Day / Evening, persisted. Starts on Auto until the stored
/// choice loads.
class AppearanceModeNotifier extends Notifier<AppearanceMode> {
  @override
  AppearanceMode build() {
    Future(() async {
      final stored = await ref.read(appearancePreferencesProvider).getMode();
      if (ref.mounted && stored != state) state = stored;
    });
    return AppearanceMode.auto;
  }

  Future<void> select(AppearanceMode mode) async {
    state = mode;
    await ref.read(appearancePreferencesProvider).setMode(mode);
  }
}

final appearanceModeProvider =
    NotifierProvider<AppearanceModeNotifier, AppearanceMode>(
  AppearanceModeNotifier.new,
);

/// Day or Evening right now. Auto switches with the dashboard clock
/// (every 30 s): Evening from the evening session start (default 17:00)
/// until morning.
final resolvedAppearanceProvider = Provider<CruAppearance>((ref) {
  return resolveAppearance(
    ref.watch(appearanceModeProvider),
    ref.watch(dashboardNowProvider),
  );
});

CruAppearance resolveAppearance(AppearanceMode mode, DateTime now) =>
    switch (mode) {
      AppearanceMode.day => CruAppearance.day,
      AppearanceMode.evening => CruAppearance.evening,
      AppearanceMode.auto =>
        isEveningSession(now) ? CruAppearance.evening : CruAppearance.day,
    };
