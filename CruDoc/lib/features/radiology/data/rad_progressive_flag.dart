import 'package:firebase_remote_config/firebase_remote_config.dart';

const String _remoteConfigFlagKey = 'rad_progressive_view';
bool _remoteConfigLoaded = false;

/// Reads Remote Config bool `rad_progressive_view` (default false).
/// Returns false on any error.
Future<bool> radProgressiveViewEnabled() async {
  // Lets a developer force the feature on: --dart-define=RAD_PROGRESSIVE=true
  if (const bool.fromEnvironment('RAD_PROGRESSIVE')) return true;

  try {
    final rc = FirebaseRemoteConfig.instance;
    if (!_remoteConfigLoaded) {
      _remoteConfigLoaded = true;
      await rc.setDefaults(const {_remoteConfigFlagKey: false});
      await rc.fetchAndActivate().timeout(const Duration(seconds: 4));
    }
    return rc.getBool(_remoteConfigFlagKey);
  } catch (_) {
    return false;
  }
}
