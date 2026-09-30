import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crudoc_shared/theme/cru_colors.dart';
import 'package:crudoc_shared/appearance/appearance_preferences.dart';
import 'package:crudoc_shared/appearance/evening_session.dart';

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
    return AppearanceMode.evening;
  }

  Future<void> select(AppearanceMode mode) async {
    state = mode;
    await ref.read(appearancePreferencesProvider).setMode(mode);
  }

  /// Toggles between Evening (Night mode) and Day mode.
  Future<void> toggle() async {
    final isCurrentlyEvening =
        state == AppearanceMode.evening ||
        (state == AppearanceMode.auto && isEveningSession(DateTime.now()));
    final next = isCurrentlyEvening
        ? AppearanceMode.day
        : AppearanceMode.evening;
    await select(next);
  }
}

final appearanceModeProvider =
    NotifierProvider<AppearanceModeNotifier, AppearanceMode>(
      AppearanceModeNotifier.new,
    );

class TextSizePreferenceNotifier extends Notifier<TextSizePreference> {
  @override
  TextSizePreference build() {
    Future(() async {
      final stored = await ref.read(appearancePreferencesProvider).getTextSize();
      if (ref.mounted && stored != state) state = stored;
    });
    return TextSizePreference.standard;
  }

  Future<void> select(TextSizePreference size) async {
    state = size;
    await ref.read(appearancePreferencesProvider).setTextSize(size);
  }
}

final textSizePreferenceProvider =
    NotifierProvider<TextSizePreferenceNotifier, TextSizePreference>(
      TextSizePreferenceNotifier.new,
    );

class DayBackgroundColorNotifier extends Notifier<int> {
  @override
  int build() {
    Future(() async {
      final stored = await ref
          .read(appearancePreferencesProvider)
          .getDayBackgroundColor();
      if (ref.mounted && stored != state) state = stored;
    });
    return AppearancePreferences.defaultDayBackgroundColor;
  }

  Future<void> select(int argb) async {
    state = argb;
    await ref.read(appearancePreferencesProvider).setDayBackgroundColor(argb);
  }
}

final dayBackgroundColorProvider =
    NotifierProvider<DayBackgroundColorNotifier, int>(
      DayBackgroundColorNotifier.new,
    );

/// Ticks every 30 s so Auto appearance flips without new data arriving.
final appearanceClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// Day or Evening right now. Auto switches with the clock (every 30 s):
/// Evening from the evening session start (default 17:00) until morning.
final resolvedAppearanceProvider = Provider<CruAppearance>((ref) {
  return resolveAppearance(
    ref.watch(appearanceModeProvider),
    ref.watch(appearanceClockProvider).value ?? DateTime.now(),
  );
});

CruAppearance resolveAppearance(AppearanceMode mode, DateTime now) =>
    switch (mode) {
      AppearanceMode.day => CruAppearance.day,
      AppearanceMode.evening => CruAppearance.evening,
      AppearanceMode.auto =>
        isEveningSession(now) ? CruAppearance.evening : CruAppearance.day,
    };
