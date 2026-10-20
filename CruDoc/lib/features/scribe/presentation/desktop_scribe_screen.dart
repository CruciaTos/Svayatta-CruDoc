// desktop_scribe_screen.dart
//
// The AI Scribe tab: today's visits on the left, the selected visit's
// consent / recording / processing / saved-note panel on the right. While
// recording, the right side widens to show the conversation as it is
// transcribed. On a phone (opened from More) the panel sits above the list.
//
// Recording and processing are driven by ScribeSessionController, the same
// state machine the phone's sheet uses. When the doctor finishes, the
// session notes are written and saved straight to the patient's record.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_session_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_recorder_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

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
    final ok = await confirmDental(
      context,
      title: 'Discard this conversation?',
      body: 'Nothing is saved to the patient’s record.',
      action: 'Discard',
    );
    if (ok) await _session?.discardRecording();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final phone = cruIsPhone(context);
    final visits = ref.watch(todaysVisitsWithPatientsProvider);
    final count = visits.value
        ?.where((v) => v.visit.status != VisitStatus.cancelled)
        .length;
    final today = DateFormat('EEEE d MMM').format(DateTime.now());
    return Padding(
      padding: phone ? CruSpace.mainPaddingPhone : CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'AI Scribe',
            subtitle: count == null
                ? today
                : '$today · ${count == 0 ? 'No visits' : count == 1 ? '1 visit' : '$count visits'}',
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final session = _session;
    final live =
        session != null &&
        (session.phase == ScribeSessionPhase.recording ||
            session.phase == ScribeSessionPhase.paused);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          if (live) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 300, child: _visitList(scrollable: true)),
                const SizedBox(width: CruSpace.cardGap),
                Expanded(child: _liveWorkspace(session)),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _visitList(scrollable: true)),
              const SizedBox(width: CruSpace.cardGap),
              SizedBox(width: 420, child: _sessionPanel(expand: true)),
            ],
          );
        }
        // Narrow (a phone, or a small window): the panel on top.
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sessionPanel(expand: false),
              const SizedBox(height: CruSpace.cardGap),
              _visitList(scrollable: false),
            ],
          ),
        );
      },
    );
  }

  // ---- Today's visits ----

  Widget _visitList({required bool scrollable}) {
    final visitsAsync = ref.watch(todaysVisitsWithPatientsProvider);
    final locked = _sessionLocked;

    final Widget content = visitsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(CruSpace.s32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      error: (e, _) => Center(
        child: DentalEmptyState(
          icon: CruIcons.warning,
          title: "Couldn't load today's visits",
          body: '$e',
        ),
      ),
      data: (all) {
        final visits =
            all.where((v) => v.visit.status != VisitStatus.cancelled).toList()
              ..sort(
                (a, b) =>
                    a.visit.scheduledStart.compareTo(b.visit.scheduledStart),
              );
        if (visits.isEmpty) {
          return const Center(
            child: DentalEmptyState(
              icon: CruIcons.calendar,
              title: 'No visits today',
              body:
                  'Book a visit in Appointments, then come back here to '
                  'record it.',
            ),
          );
        }
        final rows = [
          for (final vwp in visits)
            _VisitRow(
              visit: vwp.visit,
              patient: vwp.patient,
              selected: _visit?.id == vwp.visit.id,
              enabled: !locked || _visit?.id == vwp.visit.id,
              onTap: () => _selectVisit(vwp.visit, vwp.patient),
            ),
        ];
        if (!scrollable) {
          return Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const CruSeparator(indent: _VisitRow.indent),
                rows[i],
              ],
            ],
          );
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) =>
              const CruSeparator(indent: _VisitRow.indent),
          itemBuilder: (_, i) => rows[i],
        );
      },
    );

    return CruCard(
      semanticLabel: "Today's visits",
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s12,
        0,
        CruSpace.s12,
        CruSpace.s12,
      ),
      child: Column(
        mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalGroupLabel(
            "Today's visits",
            trailing: locked ? 'Locked while recording' : null,
          ),
          if (scrollable) Expanded(child: content) else content,
        ],
      ),
    );
  }

  // ---- The selected visit ----

  Widget _sessionPanel({required bool expand}) {
    final session = _session;
    if (session == null) {
      return const CruCard(
        semanticLabel: 'Scribe',
        padding: EdgeInsets.all(CruSpace.s12),
        child: Center(
          child: SingleChildScrollView(
            child: DentalEmptyState(
              icon: CruIcons.mic,
              title: 'Choose a visit',
              body:
                  'Pick one of today’s visits to record its consultation. '
                  'The scribe writes the session notes and saves them to the '
                  'patient’s record.',
            ),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final body = switch (session.phase) {
          ScribeSessionPhase.ready => _readyPanel(session),
          ScribeSessionPhase.done => _savedPanel(session.note!),
          ScribeSessionPhase.recording ||
          ScribeSessionPhase.paused => ScribeRecorderPanel(
            controller: session,
            onDiscard: _discardRecording,
          ),
          ScribeSessionPhase.processing => ScribeProcessingPanel(
            controller: session,
          ),
          ScribeSessionPhase.failed => ScribeFailurePanel(
            controller: session,
            onDiscard: _discardRecording,
          ),
        };
        final centred =
            session.phase != ScribeSessionPhase.ready &&
            session.phase != ScribeSessionPhase.done;

        return CruCard(
          semanticLabel: 'Scribe',
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              _PatientSummary(visit: _visit!, patient: _patient),
              const CruSeparator(),
              if (expand)
                Expanded(
                  child: centred
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(CruSpace.s24),
                            child: body,
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(CruSpace.s20),
                          child: body,
                        ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(CruSpace.s20),
                  child: body,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Recording on a wide screen: the controls in a bar, the conversation
  /// filling the card as it is heard.
  Widget _liveWorkspace(ScribeSessionController session) {
    final c = context.cru;
    final paused = session.phase == ScribeSessionPhase.paused;

    return CruCard(
      semanticLabel: 'Recording',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PatientSummary(visit: _visit!, patient: _patient),
          const CruSeparator(),
          Container(
            color: c.inset,
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s16,
              vertical: CruSpace.s10,
            ),
            child: Row(
              children: [
                ScribeStatusPill(paused: paused),
                const SizedBox(width: CruSpace.s14),
                ValueListenableBuilder<Duration>(
                  valueListenable: session.elapsed,
                  builder: (context, elapsed, _) => Text(
                    formatScribeDuration(elapsed),
                    style: CruType.title.tabular.tint(c.label),
                  ),
                ),
                const SizedBox(width: CruSpace.s16),
                Expanded(
                  child: ScribeWaveform(
                    levels: session.levels,
                    color: paused ? c.label3 : c.redText,
                    height: 28,
                  ),
                ),
                const SizedBox(width: CruSpace.s14),
                ScribeRecorderControls(
                  controller: session,
                  onDiscard: _discardRecording,
                  compact: true,
                ),
              ],
            ),
          ),
          const CruSeparator(),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              CruSpace.s8,
              CruSpace.s4,
              CruSpace.s8,
              0,
            ),
            child: DentalGroupLabel('Conversation'),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s20,
                CruSpace.s4,
                CruSpace.s20,
                CruSpace.s20,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: ScribeLiveTranscript(
                  transcript: session.transcript,
                  large: true,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s20,
              0,
              CruSpace.s20,
              CruSpace.s16,
            ),
            child: Text(
              'Talk with the patient as you normally would. When you finish, '
              'the session notes are written and saved to their record.',
              style: CruType.caption.tint(c.label2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readyPanel(ScribeSessionController session) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScribeStepsStrip(),
        const SizedBox(height: CruSpace.s24),
        Text('PATIENT CONSENT', style: CruType.groupLabel.tint(c.label3)),
        const SizedBox(height: CruSpace.s8),
        ScribeConsentCard(
          value: session.consentGiven,
          onChanged: session.setConsent,
        ),
        if (session.error != null) ...[
          const SizedBox(height: CruSpace.s14),
          ScribeNotice(tone: ScribeNoticeTone.danger, message: session.error!),
        ],
        const SizedBox(height: CruSpace.s20),
        ScribeStartButton(
          onPressed: session.consentGiven ? session.start : null,
        ),
      ],
    );
  }

  /// The session note just saved to the patient's record.
  Widget _savedPanel(ConsultationNote note) {
    final c = context.cru;
    final unsure = note.confidenceNote.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScribeNotice(
          tone: ScribeNoticeTone.success,
          title: 'Saved to the patient record',
          message:
              'Added to ${_patient?.fullName ?? 'the patient'}’s session '
              'notes.',
        ),
        const SizedBox(height: CruSpace.s20),
        Text('SESSION NOTE', style: CruType.groupLabel.tint(c.label3)),
        const SizedBox(height: CruSpace.s8),
        Text(sessionTitle(note), style: CruType.headline.tint(c.label)),
        if (unsure.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s10),
          ScribeNotice(
            tone: ScribeNoticeTone.warning,
            title: 'Check',
            message: unsure,
          ),
        ],
        const SizedBox(height: CruSpace.s10),
        Container(
          padding: const EdgeInsets.all(CruSpace.s14),
          decoration: ShapeDecoration(
            color: c.inset,
            shape: cruShape(CruRadius.control),
          ),
          child: SelectableText(
            note.notes,
            style: CruType.body.tint(c.label),
          ),
        ),
        const SizedBox(height: CruSpace.s20),
        Row(
          children: [
            Expanded(
              child: CruButton(
                label: 'Open / edit',
                icon: CruIcons.pen,
                kind: CruButtonKind.secondary,
                large: true,
                expand: true,
                onPressed: () =>
                    openSessionNote(context, note: note, patient: _patient),
              ),
            ),
            const SizedBox(width: CruSpace.s10),
            Expanded(
              child: CruButton(
                label: 'Done',
                icon: CruIcons.check,
                large: true,
                expand: true,
                onPressed: _resetToIdle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- Pieces ----

/// Scheduled (quiet), Completed (green), Missed (amber).
Widget _statusPill(CruColors c, VisitStatus status) => switch (status) {
  VisitStatus.scheduled => CruPill(
    text: 'Scheduled',
    background: c.inset,
    foreground: c.label2,
  ),
  VisitStatus.completed => CruPill(
    text: 'Completed',
    background: c.greenTint,
    foreground: c.greenText,
  ),
  VisitStatus.cancelled => CruPill(
    text: 'Cancelled',
    background: c.redTint,
    foreground: c.redText,
  ),
  VisitStatus.missed => CruPill(
    text: 'Missed',
    background: c.amberTint,
    foreground: c.amberText,
  ),
};

/// One of today's visits: who, when, where, and its status. The visit
/// being recorded stays highlighted; the others dim while it records.
class _VisitRow extends StatelessWidget {
  const _VisitRow({
    required this.visit,
    required this.patient,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  /// Separators start under the name, past the monogram.
  static const indent = CruSpace.s12 + CruSize.monogramRow + CruSpace.s12;

  final Visit visit;
  final Patient? patient;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final name = patient?.fullName ?? 'Unknown patient';
    final where = visit.visitType == VisitType.home ? 'Home visit' : 'Clinic';
    return AnimatedOpacity(
      duration: CruMotion.of(context, CruMotion.fast),
      opacity: enabled ? 1 : 0.45,
      child: CruPressable(
        onTap: enabled ? onTap : null,
        scaleOnPress: false,
        semanticLabel: '$name, ${DateFormat('h:mm a').format(visit.scheduledStart)}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s8,
          ),
          decoration: ShapeDecoration(
            color: selected
                ? c.accentTint
                : hovered && enabled
                ? c.hoverFill
                : c.hoverFill.withValues(alpha: 0),
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            children: [
              CruMonogram(name: name),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.row.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      '${DateFormat('h:mm a').format(visit.scheduledStart)} · $where',
                      style: CruType.subhead.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              _statusPill(c, visit.status),
              if (selected) ...[
                const SizedBox(width: CruSpace.s8),
                CruIcon(CruIcons.check, size: 18, color: c.accentText),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is being seen: name, sex and age, time and where.
class _PatientSummary extends StatelessWidget {
  const _PatientSummary({required this.visit, required this.patient});

  final Visit visit;
  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = patient;
    final name = p?.fullName ?? 'Unknown patient';
    final details = [
      if (p != null) '${p.gender}, ${p.age} yrs',
      DateFormat('h:mm a').format(visit.scheduledStart),
      visit.visitType == VisitType.home ? 'Home visit' : 'Clinic',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Row(
        children: [
          CruMonogram(name: name, vibrant: true),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.headline.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.subhead.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
