import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'activity_last_seen_ms';

/// When Notifications was last opened. Null until loaded, or if never
/// opened.
final activitySeenProvider = NotifierProvider<ActivitySeen, DateTime?>(
  ActivitySeen.new,
);

class ActivitySeen extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key);
    if (ms != null) state = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markSeen() async {
    final now = DateTime.now();
    state = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, now.millisecondsSinceEpoch);
  }
}
