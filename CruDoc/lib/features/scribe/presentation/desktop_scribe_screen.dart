// desktop_scribe_screen.dart
//
// Full-panel AI Voice Scribe screen for the desktop shell.
//
// Rendered as a SizedBox.expand content-area widget with the same glass
// container and header as DesktopQueueScreen / DesktopEventsScreen, so the
// sidebar stays visible throughout the recording → review flow.
//
// Layout: today's visits on the left, the selected visit's consent /
// recording / processing / saved-note panel on the right. While recording,
// the right side widens to show the conversation as it is transcribed.
//
// Recording and processing are driven by ScribeSessionController — the same
// state machine the mobile sheet uses. When the doctor finishes, the
// session notes are written and saved straight to the patient's record.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_session_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_palette.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_recorder_widgets.dart';

const ScribePalette _p = ScribePalette.desktop;

class DesktopScribeScreen extends ConsumerStatefulWidget {
  const DesktopScribeScreen({super.key});

  @override
  ConsumerState<DesktopScribeScreen> createState() =>
      _DesktopScribeScreenState();
}

class _DesktopScribeScreenState extends ConsumerState<DesktopScribeScreen> {
  Visit? _visit;
  Patient? _patient;
  ScribeSessionController? _session;

  @override
  void dispose() {
    _disposeSession();
    super.dispose();
  }

  // ---- Session lifecycle ----

  /// Switching visits would drop the conversation being recorded.
  bool get _sessionLocked => _session?.hasUnsavedConversation ?? false;

  void _selectVisit(Visit visit, Patient? patient) {
    if (_sessionLocked) return;
    if (_visit?.id == visit.id) return;
    _disposeSession();
    final session = ScribeSessionController(
      visit: visit,
      processingService: ref.read(scribeProcessingServiceProvider),
      repository: ref.read(consultationNoteRepositoryProvider),
    )..addListener(_onSessionChanged);
    setState(() {
      _visit = visit;
      _patient = patient;
      _session = session;
    });
  }

  void _onSessionChanged() => setState(() {});

  void _disposeSession() {
    _session
      ?..removeListener(_onSessionChanged)
      ..dispose();
    _session = null;
  }

  void _resetToIdle() {
    _disposeSession();
    setState(() {
      _visit = null;
      _patient = null;
    });
  }

  Future<void> _discardRecording() async {
    final ok = await showScribeConfirmDialog(
      context,
      palette: _p,
      icon: Icons.delete_outline_rounded,
      title: 'Discard this conversation?',
      message: 'Nothing is saved to the patient’s record.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep',
    );
    if (ok) await _session?.discardRecording();
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSessionHeader(),
                  const SizedBox(height: 20),
                  Expanded(child: _buildSessionBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Headers ----

  Widget _buildSessionHeader() {
    return _PageHeader(
      icon: Icons.mic_rounded,
      title: 'AI Voice Scribe',
      subtitle:
          'Talk with the patient — the scribe writes the session notes and '
          'saves them to their record',
      pill: DateFormat('EEEE, MMM d').format(DateTime.now()),
    );
  }

  // ---- Session (visit picker + recorder) ----

  Widget _buildSessionBody() {
    final session = _session;
    final isLiveRecording =
        session != null &&
        (session.phase == ScribeSessionPhase.recording ||
            session.phase == ScribeSessionPhase.paused);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          if (isLiveRecording) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 300, child: _buildVisitList(scrollable: true)),
                const SizedBox(width: 20),
                Expanded(child: _buildLiveRecordingWorkspace(session)),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildVisitList(scrollable: true)),
              const SizedBox(width: 20),
              SizedBox(width: 420, child: _buildSessionPanel(expand: true)),
            ],
          );
        }
        if (isLiveRecording) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLiveRecordingWorkspace(session),
                const SizedBox(height: 16),
                _buildVisitList(scrollable: false),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSessionPanel(expand: false),
              const SizedBox(height: 16),
              _buildVisitList(scrollable: false),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisitList({required bool scrollable}) {
    final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);
    final locked = _sessionLocked;

    Widget content = visitsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      error: (e, _) => _EmptyState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load today's visits",
        message: '$e',
      ),
      data: (all) {
        final visits =
            all.where((v) => v.visit.status != VisitStatus.cancelled).toList()
              ..sort(
                (a, b) =>
                    a.visit.scheduledStart.compareTo(b.visit.scheduledStart),
              );
        if (visits.isEmpty) {
          return const _EmptyState(
            icon: Icons.event_busy_rounded,
            title: 'No visits today',
            message:
                'Schedule a visit in Appointments, then come back to '
                'record it.',
          );
        }
        final tiles = [
          for (final vwp in visits)
            _VisitTile(
              visit: vwp.visit,
              patient: vwp.patient,
              selected: _visit?.id == vwp.visit.id,
              enabled: !locked || _visit?.id == vwp.visit.id,
              onTap: () => _selectVisit(vwp.visit, vwp.patient),
            ),
        ];
        if (!scrollable) {
          return Column(children: tiles);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          itemCount: tiles.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (_, i) => tiles[i],
        );
      },
    );

    final count = visitsAsync.value
        ?.where((v) => v.visit.status != VisitStatus.cancelled)
        .length;

    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          "TODAY'S VISITS",
                          style: _p.sectionLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _p.field,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _p.border),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _p.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (locked) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message:
                        'Finish or discard the current conversation to switch visits',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: _p.hint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Locked',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _p.hint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (scrollable)
            Expanded(child: content)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: content,
            ),
        ],
      ),
    );
  }

  Widget _buildSessionPanel({required bool expand}) {
    final session = _session;
    if (session == null) {
      return _Card(
        child: const _EmptyState(
          icon: Icons.touch_app_outlined,
          title: 'Select a visit',
          message:
              'Choose one of today’s visits to start recording its '
              'consultation.',
        ),
      );
    }

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final body = switch (session.phase) {
          ScribeSessionPhase.ready => _buildReadyPanel(session),
          ScribeSessionPhase.done => _buildSavedPanel(session.note!),
          ScribeSessionPhase.recording ||
          ScribeSessionPhase.paused => ScribeRecorderPanel(
            controller: session,
            palette: _p,
            onDiscard: _discardRecording,
          ),
          ScribeSessionPhase.processing => ScribeProcessingPanel(
            controller: session,
            palette: _p,
          ),
          ScribeSessionPhase.failed => ScribeFailurePanel(
            controller: session,
            palette: _p,
            onDiscard: _discardRecording,
          ),
        };
        final centred =
            session.phase != ScribeSessionPhase.ready &&
            session.phase != ScribeSessionPhase.done;

        return _Card(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              _PatientSummary(visit: _visit!, patient: _patient),
              Divider(height: 1, color: _p.border),
              if (expand)
                Expanded(
                  child: centred
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: body,
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: body,
                        ),
                )
              else
                Padding(padding: const EdgeInsets.all(20), child: body),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveRecordingWorkspace(ScribeSessionController session) {
    final paused = session.phase == ScribeSessionPhase.paused;
    final statusColor = paused ? _p.warning : _p.danger;

    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PatientSummary(visit: _visit!, patient: _patient),
          Divider(height: 1, color: _p.border),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _p.field,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        paused ? 'PAUSED' : 'LISTENING',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                ValueListenableBuilder<Duration>(
                  valueListenable: session.elapsed,
                  builder: (context, elapsed, _) => Text(
                    formatScribeDuration(elapsed),
                    style: TextStyle(
                      fontFamily: AppColors.headingFontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _p.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: ScribeWaveform(
                      levels: session.levels,
                      color: paused ? _p.hint : _p.danger,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                IconButton(
                  tooltip: paused ? 'Resume recording' : 'Pause recording',
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  ),
                  color: _p.textPrimary,
                  onPressed: paused ? session.resume : session.pause,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Discard recording',
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: _p.textSecondary,
                  onPressed: _discardRecording,
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: session.finish,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Finish & write notes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _p.primary,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _p.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('CONVERSATION', style: _p.sectionLabel),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Align(
                alignment: Alignment.topLeft,
                child: ScribeLiveTranscript(
                  transcript: session.transcript,
                  palette: _p,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'Talk with the patient as you normally would. When you '
              'finish, the session notes are written and saved to their '
              'record.',
              style: TextStyle(fontSize: 12.5, color: _p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyPanel(ScribeSessionController session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScribeStepsStrip(palette: _p),
        const SizedBox(height: 22),
        Text('PATIENT CONSENT', style: _p.sectionLabel),
        const SizedBox(height: 10),
        ScribeConsentCard(
          value: session.consentGiven,
          onChanged: session.setConsent,
          palette: _p,
          background: _p.field,
        ),
        if (session.error != null) ...[
          const SizedBox(height: 14),
          ScribeNotice(
            icon: Icons.error_outline_rounded,
            color: _p.danger,
            background: _p.dangerSoft,
            message: session.error!,
          ),
        ],
        const SizedBox(height: 20),
        ScribePrimaryButton(
          label: 'Start recording',
          icon: Icons.mic_rounded,
          color: _p.primary,
          onPressed: session.consentGiven ? session.start : null,
        ),
      ],
    );
  }

  /// The session note just saved to the patient's record.
  Widget _buildSavedPanel(ConsultationNote note) {
    final unsure = note.confidenceNote.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScribeNotice(
          icon: Icons.check_circle_rounded,
          color: _p.success,
          background: _p.success.withValues(alpha: 0.08),
          title: 'Saved to the patient record',
          message:
              'Added to ${_patient?.fullName ?? 'the patient'}’s session '
              'notes.',
        ),
        const SizedBox(height: 20),
        Text('SESSION NOTE', style: _p.sectionLabel),
        const SizedBox(height: 10),
        Text(
          sessionTitle(note),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _p.textPrimary,
          ),
        ),
        if (unsure.isNotEmpty) ...[
          const SizedBox(height: 10),
          ScribeNotice(
            icon: Icons.warning_amber_rounded,
            color: _p.warning,
            background: _p.warningSoft,
            title: 'Check',
            message: unsure,
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _p.field,
            borderRadius: BorderRadius.circular(_p.fieldRadius),
            border: Border.all(color: _p.border),
          ),
          child: SelectableText(
            note.notes,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: _p.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    openSessionNote(context, note: note, patient: _patient),
                icon: const Icon(Icons.edit_note_rounded, size: 20),
                label: const Text('Open / edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _p.textPrimary,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: _p.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ScribePrimaryButton(
                label: 'Done',
                icon: Icons.check_rounded,
                color: _p.primary,
                onPressed: _resetToIdle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ===========================================================================
// Pieces
// ===========================================================================

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.pill,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? pill;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _p.accentSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _p.accent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _p.textPrimary,
                        fontFamily: AppColors.headingFontFamily,
                      ),
                    ),
                  ),
                  if (pill != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _p.field,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _p.border),
                      ),
                      child: Text(
                        pill!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _p.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: _p.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(_p.cardRadius),
        border: Border.all(color: _p.cardBorder),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _p.field,
                shape: BoxShape.circle,
                border: Border.all(color: _p.border),
              ),
              child: Icon(icon, color: _p.textSecondary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _p.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _initials(Patient? patient) {
  final name = patient?.fullName.trim() ?? '';
  if (name.isEmpty) return '?';
  final parts = name.split(RegExp(r'\s+'));
  final first = parts.first.characters.first;
  final last = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$last'.toUpperCase();
}

(Color, String) _statusStyle(VisitStatus status) => switch (status) {
  VisitStatus.scheduled => (_p.accent, 'Scheduled'),
  VisitStatus.completed => (_p.success, 'Completed'),
  VisitStatus.cancelled => (_p.danger, 'Cancelled'),
  VisitStatus.missed => (_p.warning, 'Missed'),
};

class _VisitTile extends StatelessWidget {
  const _VisitTile({
    required this.visit,
    required this.patient,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Visit visit;
  final Patient? patient;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel) = _statusStyle(visit.status);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: selected ? _p.accentSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? _p.accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          hoverColor: _p.field,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: selected ? _p.accent : _p.field,
                  child: Text(
                    _initials(patient),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : _p.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient?.fullName ?? 'Unknown patient',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${DateFormat('h:mm a').format(visit.scheduledStart)}'
                        ' · ${visit.visitType == VisitType.home ? 'Home visit' : 'Clinic'}',
                        style: TextStyle(fontSize: 12, color: _p.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle_rounded, color: _p.accent, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientSummary extends StatelessWidget {
  const _PatientSummary({required this.visit, required this.patient});

  final Visit visit;
  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final p = patient;
    final details = [
      if (p != null) '${p.gender}, ${p.age} yrs',
      DateFormat('h:mm a').format(visit.scheduledStart),
      visit.visitType == VisitType.home ? 'Home visit' : 'Clinic',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _p.accent,
            child: Text(
              _initials(p),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p?.fullName ?? 'Unknown patient',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: _p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
