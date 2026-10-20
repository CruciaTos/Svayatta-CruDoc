import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart'
    show confirmDental;
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_session_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_recorder_widgets.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Runs the mobile scribe flow for [visit]: the recording sheet, then the
/// session note it saved to the patient's record.
///
/// Returns true if a session note was saved, so the caller can refresh
/// anything showing the visit's notes.
///
/// Pass [queueEntryId] (and [tokenNumber]) when the consultation was just
/// started from the queue: the sheet then asks for the patient's consent
/// and starts recording in a single tap.
Future<bool> showScribeFlow(
  BuildContext context, {
  required Visit visit,
  Patient? patient,
  String specialty = SessionSpecialty.none,
  String? queueEntryId,
  int? tokenNumber,
}) async {
  final note = await showModalBottomSheet<ConsultationNote>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Drag-to-dismiss would bypass the "discard recording?" check.
    enableDrag: false,
    backgroundColor: context.cru.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ScribeRecordingSheet(
      visit: visit,
      patient: patient,
      specialty: specialty,
      queueEntryId: queueEntryId,
      tokenNumber: tokenNumber,
    ),
  );
  if (note == null) return false;
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Session note saved to ${patient?.fullName ?? 'the patient'}’s '
          'record.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await openSessionNote(context, note: note, patient: patient);
  }
  return true;
}

/// Bottom sheet that captures patient consent and listens to the
/// consultation, then writes the session notes and saves them to the
/// patient's record.
///
/// Pops with the saved session [ConsultationNote], or null if the doctor
/// closed it first. Use [showScribeFlow] to open it.
class ScribeRecordingSheet extends ConsumerStatefulWidget {
  final Visit visit;
  final Patient? patient;
  final String specialty;
  final String? queueEntryId;
  final int? tokenNumber;

  const ScribeRecordingSheet({
    super.key,
    required this.visit,
    required this.patient,
    this.specialty = SessionSpecialty.none,
    this.queueEntryId,
    this.tokenNumber,
  });

  /// Opened by starting a consultation from the queue.
  bool get startedFromQueue => queueEntryId != null;

  @override
  ConsumerState<ScribeRecordingSheet> createState() =>
      _ScribeRecordingSheetState();
}

class _ScribeRecordingSheetState extends ConsumerState<ScribeRecordingSheet> {
  late final ScribeSessionController _session;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _session = ScribeSessionController(
      visit: widget.visit,
      processingService: ref.read(scribeProcessingServiceProvider),
      repository: ref.read(consultationNoteRepositoryProvider),
      specialty: widget.specialty,
      queueEntryId: widget.queueEntryId,
    )..addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session
      ..removeListener(_onSessionChanged)
      ..dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final note = _session.note;
    if (_session.phase == ScribeSessionPhase.done && note != null) {
      _close(note);
    }
  }

  void _close([ConsultationNote? note]) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(context, note);
  }

  /// Close button / back gesture: confirm before losing a recording.
  Future<void> _requestClose() async {
    if (_session.phase == ScribeSessionPhase.processing) {
      final leave = await confirmDental(
        context,
        title: 'Still writing the notes',
        body:
            "If you close now, the session note is still saved to the "
            "patient's record once it's written.",
        action: 'Close anyway',
      );
      if (leave) _close();
      return;
    }
    if (_session.hasUnsavedConversation) {
      final discard = await _confirmDiscard();
      if (!discard) return;
      await _session.discardRecording();
    }
    _close();
  }

  Future<bool> _confirmDiscard() {
    return confirmDental(
      context,
      title: 'Discard this conversation?',
      body: 'Nothing is saved to the patient’s record.',
      action: 'Discard',
    );
  }

  Future<void> _discardRecording() async {
    if (await _confirmDiscard()) await _session.discardRecording();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final canPopFreely = !_session.hasUnsavedConversation;
        return PopScope(
          canPop: canPopFreely,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _requestClose();
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 16, 24 + bottomInset),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  _LastSessionTile(
                    patientId: widget.visit.patientId,
                    patient: widget.patient,
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey(_bodyKey),
                        child: _buildBody(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Recording and paused share a body so the timer doesn't cross-fade.
  String get _bodyKey => switch (_session.phase) {
    ScribeSessionPhase.recording || ScribeSessionPhase.paused => 'recording',
    final phase => phase.name,
  };

  Widget _buildHeader() {
    final c = context.cru;
    final patientName = widget.patient?.fullName ?? 'Unknown patient';
    final when = DateFormat(
      'd MMM, h:mm a',
    ).format(widget.visit.scheduledStart);
    final token = widget.tokenNumber;
    return Row(
      children: [
        const CruIconTile(icon: CruIcons.mic, tone: CruTileTone.accent),
        const SizedBox(width: CruSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('AI Scribe', style: CruType.title.tint(c.label)),
              ),
              const SizedBox(height: CruSpace.s2),
              Text(
                [
                  if (token != null) 'Token $token',
                  patientName,
                  when,
                ].join(' · '),
                style: CruType.subhead.tabular.tint(c.label2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        CruIconButton(
          icon: CruIcons.close,
          semanticLabel: 'Close',
          tooltip: 'Close',
          onPressed: _requestClose,
        ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_session.phase) {
      case ScribeSessionPhase.ready:
      case ScribeSessionPhase.done:
        return _buildReady();
      case ScribeSessionPhase.recording:
      case ScribeSessionPhase.paused:
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: ScribeRecorderPanel(
            controller: _session,
            onDiscard: _discardRecording,
          ),
        );
      case ScribeSessionPhase.processing:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: ScribeProcessingPanel(controller: _session),
        );
      case ScribeSessionPhase.failed:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ScribeFailurePanel(
            controller: _session,
            onDiscard: _discardRecording,
          ),
        );
    }
  }

  Widget _buildReady() {
    if (widget.startedFromQueue) return _buildQueueReady();
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScribeStepsStrip(),
        const SizedBox(height: CruSpace.s24),
        Text('PATIENT CONSENT', style: CruType.groupLabel.tint(c.label3)),
        const SizedBox(height: CruSpace.s8),
        ScribeConsentCard(
          value: _session.consentGiven,
          onChanged: _session.setConsent,
        ),
        if (_session.error != null) ...[
          const SizedBox(height: CruSpace.s14),
          ScribeNotice(
            tone: ScribeNoticeTone.danger,
            message: _session.error!,
          ),
        ],
        const SizedBox(height: CruSpace.s20),
        ScribeStartButton(
          onPressed: _session.consentGiven ? _session.start : null,
        ),
      ],
    );
  }

  /// The consultation has just started: ask the patient, then one tap both
  /// records their consent and starts recording.
  Widget _buildQueueReady() {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('BEFORE YOU BEGIN', style: CruType.groupLabel.tint(c.label3)),
        const SizedBox(height: CruSpace.s8),
        Text(
          'Ask the patient if this consultation can be recorded. The '
          'conversation is transcribed and an AI writes the session note '
          'from it; the recording is deleted from this device as soon as it '
          'stops.',
          style: CruType.text.tint(c.label2),
        ),
        if (_session.error != null) ...[
          const SizedBox(height: CruSpace.s14),
          ScribeNotice(
            tone: ScribeNoticeTone.danger,
            message: _session.error!,
          ),
        ],
        const SizedBox(height: CruSpace.s20),
        CruButton(
          label: 'Patient agreed, start recording',
          icon: CruIcons.mic,
          large: true,
          expand: true,
          onPressed: _session.consentAndStart,
        ),
        const SizedBox(height: CruSpace.s12),
        Center(
          child: CruLink(
            label: 'Patient declined, don’t record',
            color: c.label2,
            onPressed: _close,
          ),
        ),
      ],
    );
  }
}

/// The patient's previous session, one tap away while they're being seen.
/// Hidden for a first visit.
class _LastSessionTile extends ConsumerWidget {
  const _LastSessionTile({required this.patientId, required this.patient});

  final String patientId;
  final Patient? patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionHistoryProvider(patientId)).value;
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();
    final last = sessions.first;
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s16, right: CruSpace.s8),
      child: CruPressable(
        onTap: () => openSessionNote(context, note: last, patient: patient),
        semanticLabel: 'Open the last session',
        scaleOnPress: false,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s10,
          ),
          decoration: BoxDecoration(
            color: hovered ? c.hoverFill : c.inset,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CruIcon(CruIcons.clock, size: 18, color: c.label2),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Last session · '
                      '${DateFormat('d MMM yyyy').format(last.createdAt)}',
                      style: CruType.subhead.tabular.tint(c.label2),
                    ),
                    Text(
                      sessionTitle(last),
                      style: CruType.callout.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              CruIcon(CruIcons.chevronRight, size: 18, color: c.label3),
            ],
          ),
        ),
      ),
    );
  }
}
