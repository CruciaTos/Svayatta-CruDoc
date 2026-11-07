import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/update/models/update_check_result.dart';
import 'package:doctor_management_app/features/update/controllers/update_controller.dart';
import 'package:doctor_management_app/features/update/presentation/update_available_dialog.dart';

/// Looks for a new GitHub release a few seconds after the app opens and
/// then every few hours while it stays open, and shows the "Update
/// available" dialog (Update now / Later / Skip this version) once per
/// version. A release flagged forceUpdate can't be dismissed.
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
  static const _firstCheckDelay = Duration(seconds: 8);
  static const _recheckEvery = Duration(hours: 6);

  Timer? _first;
  Timer? _again;
  String? _prompted;

  static bool get _enabled =>
      !kIsWeb && !kDebugMode && (Platform.isAndroid || Platform.isWindows);

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    ref.listenManual(updateControllerProvider, (_, next) => _prompt(next));
    _first = Timer(_firstCheckDelay, _check);
    _again = Timer.periodic(_recheckEvery, (_) {
      // Someone who said "Later" is asked again.
      _prompted = null;
      _check();
    });
  }

  @override
  void dispose() {
    _first?.cancel();
    _again?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted) return;
    try {
      await ref.read(updateControllerProvider.notifier).checkForUpdate();
    } catch (e) {
      debugPrint('[UpdateLauncher] $e');
    }
  }

  void _prompt(UpdateControllerState state) {
    final result = state.checkResult;
    if (!mounted || result is! UpdateAvailable) return;
    if (state.dismissedForSession || state.progress != null) return;
    final release = result.release;
    if (_prompted == release.version) return;
    _prompted = release.version;
    showUpdateAvailableDialog(context, release);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
