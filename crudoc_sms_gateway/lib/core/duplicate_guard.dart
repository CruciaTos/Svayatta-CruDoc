import 'package:shared_preferences/shared_preferences.dart';

/// Prevents duplicate SMS from being sent when the same requestId is received
/// more than once (e.g. due to network retries).
///
/// Stores a local cache of processed request IDs along with their results.
/// When a duplicate requestId arrives, the cached result is returned
/// without re-triggering the SIM card.
class DuplicateGuard {
  DuplicateGuard._();
  static final DuplicateGuard instance = DuplicateGuard._();

  static const _prefix = 'sms_req_';
  static const _maxCacheSize = 500;

  /// Checks if a requestId has already been processed.
  Future<bool> isDuplicate(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_prefix$requestId');
  }

  /// Returns the cached result for a previously processed requestId.
  Future<String?> getCachedResult(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$requestId');
  }

  /// Records a processed requestId and its result.
  Future<void> record(String requestId, String resultJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$requestId', resultJson);

    // Track insertion order for cache eviction
    final keys = prefs.getStringList('sms_req_order') ?? [];
    keys.add(requestId);

    // Evict oldest entries if cache exceeds max size
    if (keys.length > _maxCacheSize) {
      final evictCount = keys.length - _maxCacheSize;
      for (var i = 0; i < evictCount; i++) {
        await prefs.remove('$_prefix${keys[i]}');
      }
      keys.removeRange(0, evictCount);
    }

    await prefs.setStringList('sms_req_order', keys);
  }
}
