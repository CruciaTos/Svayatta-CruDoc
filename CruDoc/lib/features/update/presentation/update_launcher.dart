import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/features/update/presentation/update_available_dialog.dart';

/// Looks for a new GitHub release whenever the app is opened: shortly
/// after launch, each time it comes back from the background, and every
/// few hours while it stays open (a PC left on all day). If one is found
/// the "Update available" dialog (Update now / Later / Skip this version)
/// is shown once for that check, so "Later" only lasts until the app is
/// opened again. A release flagged forceUpdate can't be dismissed.
/// Failed checks (offline, GitHub busy) show nothing.
///
/// Windows and Android only (the platforms with an in-app installer), and
/// never in debug runs, so a developer's own build isn't replaced by the
/// last release. Settings › Check for updates still works everywhere.
class UpdateLauncher extends ConsumerStatefulWidget {
  const UpdateLauncher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateLauncher> createState() => _UpdateLauncherState();
}

class _UpdateLauncherState extends ConsumerState<UpdateLauncher> {
  static const _firstCheckDelay = Duration(seconds: 3);
  static const _recheckEvery = Duration(hours: 6);

  /// Trips out to the camera, a file picker or the share sheet put the
  /// app in the background for a few seconds; those aren't "opening the
  /// app" and shouldn't bring up the dialog mid-task.
  static const _minTimeAway = Duration(seconds: 30);

  Timer? _first;
  Timer? _again;
  AppLifecycleListener? _lifecycle;
  DateTime? _wentAwayAt;

  /// True between the start of an automatic check and the first time its
  /// result could be shown; cleared once the dialog has been offered, so
  /// each launch or resume prompts at most once.
  bool _mayPrompt = false;
  bool _dialogOpen = false;

  static bool get _enabled =>
      !kIsWeb && !kDebugMode && (Platform.isAndroid || Platform.isWindows);

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    ref.listenManual(updateControllerProvider, (_, next) => _prompt(next));
    _first = Timer(_firstCheckDelay, _check);
    _again = Timer.periodic(_recheckEvery, (_) => _check());
    _lifecycle = AppLifecycleListener(
      // Hidden (minimised on Windows, backgrounded on Android) — not just
      // losing focus to another window, which is only "inactive".
      onHide: () => _wentAwayAt ??= DateTime.now(),
      onShow: () {
        final since = _wentAwayAt;
        _wentAwayAt = null;
        if (since != null && DateTime.now().difference(since) >= _minTimeAway) {
          _check();
        }
      },
    );
  }

  @override
  void dispose() {
    _first?.cancel();
    _again?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted) return;
    _mayPrompt = true;
    try {
      await ref.read(updateControllerProvider.notifier).checkForUpdate();
    } catch (e) {
      debugPrint('[UpdateLauncher] $e');
    }
    if (!mounted) return;
    // The check may have been skipped (one ran moments ago) without
    // changing state; offer what the last check found, if anything.
    _prompt(ref.read(updateControllerProvider));
  }

  void _prompt(UpdateControllerState state) {
    if (!mounted || !_mayPrompt || _dialogOpen || state.isChecking) return;
    final result = state.checkResult;
    if (result is! UpdateAvailable) return;
    if (state.dismissedForSession || state.progress != null) return;
    _mayPrompt = false;
    _dialogOpen = true;
    showUpdateAvailableDialog(context, result.release).whenComplete(() {
      _dialogOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
