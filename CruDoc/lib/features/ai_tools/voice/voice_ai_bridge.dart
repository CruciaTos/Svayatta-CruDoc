import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/ai_consent.dart';
import 'package:doctor_management_app/core/utils/app_notice.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/voice/domain/voice_navigation.dart';

import '../core/ai_agent.dart';
import '../core/ai_tool.dart';
import '../core/ai_tool_executor.dart';
import '../tools/all_tools.dart';

/// Hands speech the keyword rules did not understand to the AI tool agent.
/// Created by the voice controller, which supplies the pill's hooks (what to
/// say, how to ask Yes / No, how to open a screen) so the tab and spot logic
/// stays in one place.
class VoiceAiBridge {
  VoiceAiBridge({
    required WidgetRef ref,
    required BuildContext Function() context,
    required void Function(String text) say,
    required Future<bool> Function(String text) askYesNo,
    required void Function(NavTarget target) openTarget,
    void Function(Patient patient)? onPatientOpened,
  }) : _ref = ref,
       _context = context,
       _say = say,
       _askYesNo = askYesNo,
       _openTarget = openTarget,
       _onPatientOpened = onPatientOpened;

  final WidgetRef _ref;
  final BuildContext Function() _context;
  final void Function(String text) _say;
  final Future<bool> Function(String text) _askYesNo;
  final void Function(NavTarget target) _openTarget;
  final void Function(Patient patient)? _onPatientOpened;

  static const _idle = Duration(minutes: 2);
  static const _minWords = 3;

  AiAgent? _agent;
  Timer? _idleTimer;
  bool _busy = false;
  bool _disposed = false;

  /// Said after the model's own reply (e.g. where to find Reports).
  String? _note;

  AiAgent get _agentOrNew =>
      _agent ??= () {
        final registry = _ref.read(aiToolRegistryProvider);
        return AiAgent(
          registry: registry,
          executor: AiToolExecutor(
            registry,
            confirm: (tool, text) => _askYesNo(text),
          ),
        );
      }();

  /// Forget the conversation (overlay closed, or idle for 2 minutes).
  void reset() {
    _idleTimer?.cancel();
    _agent?.reset();
    _agent = null;
  }

  void dispose() {
    _disposed = true;
    reset();
  }

  /// Runs [text] through the agent. Does nothing for short phrases, when a
  /// request is already running, or when this login may not use AI.
  Future<void> handle(String text) async {
    if (_busy || _disposed) return;
    if (text.trim().split(RegExp(r'\s+')).length < _minWords) return;
    if (!_ref.read(clinicCanProvider(ClinicPermission.ai))) return;

    _busy = true;
    _idleTimer?.cancel();
    _note = null;
    try {
      if (!await AiConsent.granted) {
        if (!_disposed) _say(const AiConsentRequired().toString());
        return;
      }
      _say('Thinking…');
      final reply = await _agentOrNew.send(_buildContext(), text);
      if (_disposed) return;
      _say(
        [
          reply.text.isEmpty ? 'Done' : reply.text,
          ?_note,
        ].join(' · '),
      );
      _offerUndo(reply);
    } on AiConsentRequired catch (e) {
      if (!_disposed) _say(e.toString());
    } catch (e, st) {
      debugPrint('[VoiceAiBridge] $e\n$st');
      if (!_disposed) _say("Couldn't do that");
    } finally {
      _busy = false;
      if (!_disposed) _idleTimer = Timer(_idle, reset);
    }
  }

  AiToolContext _buildContext() {
    final shell = _ref.read(shellNavigatorProvider) != null;
    final details = shell
        ? _ref.read(patientsListControllerProvider).detailsId
        : null;
    final onDetails =
        shell &&
        details != null &&
        _ref.read(shellCurrentTabProvider) == DesktopTab.patients;
    return AiToolContext(
      read: _ref.read,
      invalidate: _ref.invalidate,
      access: _ref.read(clinicAccessProvider).value,
      navigate: _navigate,
      screen: onDetails ? 'patient_details' : _screen(shell),
      openPatientId: onDetails ? details : null,
    );
  }

  String? _screen(bool shell) {
    if (!shell) {
      return switch (_ref.read(mobileCurrentTabProvider)) {
        MobileTab.home => 'dashboard',
        MobileTab.schedule => 'appointments',
        MobileTab.patients => 'patients',
        _ => null,
      };
    }
    return switch (_ref.read(shellCurrentTabProvider)) {
      DesktopTab.dashboard => 'dashboard',
      DesktopTab.patients => 'patients',
      DesktopTab.inventory => 'inventory',
      DesktopTab.revenue => 'revenue',
      DesktopTab.appointments => 'appointments',
      DesktopTab.queue => 'queue',
      DesktopTab.campaigns => 'campaigns',
      DesktopTab.files => 'files',
      DesktopTab.settings => 'settings',
      DesktopTab.charting => 'charting',
      DesktopTab.todos => 'todos',
      _ => null,
    };
  }

  /// `tab:` / `spot:` go to the voice controller; the rest are opened here
  /// with the same actions the screens use.
  Future<void> _navigate(
    String target, {
    Map<String, Object?> args = const {},
  }) async {
    if (target == 'patient' || target.startsWith('report:')) {
      final id = args['patientId'];
      if (id is! String) return;
      final patient = await _ref.read(patientRepositoryProvider).getPatient(id);
      if (patient == null || _disposed) return;
      DashboardActions.openPatient(_context(), patient);
      _onPatientOpened?.call(patient);
      if (target.startsWith('report:')) {
        _note = 'Open Reports from the patient page';
      }
      return;
    }
    if (target.startsWith('file:')) {
      final id = args['fileId'];
      if (id is! String) return;
      final file = await FilesRepository.instance.file(id);
      if (file == null || _disposed) return;
      final owner = await _ref
          .read(patientRepositoryProvider)
          .getPatient(file.patientId);
      if (_disposed) return;
      await FilesActions.open(
        _context(),
        file,
        patientName: owner?.fullName.trim() ?? '',
      );
      return;
    }
    final t = targetFromOption(target);
    if (t != null) _openTarget(t);
  }

  /// Undo for the writes the agent made: an island notice with an Undo
  /// action, or a SnackBar when no island is on screen.
  void _offerUndo(AiAgentReply reply) {
    final undos = reply.undos;
    if (undos.isEmpty) return;
    final summary = reply.steps
        .lastWhere((s) => s.result.undo != null)
        .result
        .summary;
    final text = summary ?? 'Done';

    Future<void> undoAll() async {
      for (final undo in undos) {
        try {
          await undo();
        } catch (e) {
          debugPrint('[VoiceAiBridge] undo failed: $e');
        }
      }
      if (!_disposed) _say('Undone');
    }

    if (AppNotices.hosted) {
      AppNotices.show(
        AppNotice(
          text: text,
          actionLabel: 'Undo',
          onAction: () => unawaited(undoAll()),
          duration: const Duration(seconds: 8),
        ),
      );
    } else {
      ScaffoldMessenger.maybeOf(_context())?.showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(undoAll()),
          ),
        ),
      );
    }
  }
}
