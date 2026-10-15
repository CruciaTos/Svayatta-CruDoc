import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_review_screen.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_session_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_draft_form.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_palette.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_recorder_widgets.dart';
import 'package:doctor_management_app/features/scribe/presentation/session_note_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Runs the mobile scribe flow for [visit]: the recording sheet, then the
/// review screen for the resulting draft.
///
/// Returns true if the doctor confirmed a note into the patient record, so
/// the caller can refresh anything showing the visit's notes.
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
  final draft = await showModalBottomSheet<ConsultationNote>(
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
  if (draft == null || !context.mounted) return false;

  final confirmed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ScribeDraftReviewScreen(note: draft, patient: patient),
    ),
  );
  return confirmed ?? false;
}

/// Bottom sheet that captures patient consent and records the consultation.
///
/// Pops with the resulting draft [ConsultationNote] (AI-generated, resumed,
/// or blank for manual entry), or null if the doctor closed it. Nothing is
/// written to the patient record here — that only happens on Confirm in
/// [ScribeDraftReviewScreen]. Use [showScribeFlow] to open it.
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
  ScribePalette get _palette => ScribePalette.of(context);

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
    _session.loadPendingDraft();
  }

  @override
  void dispose() {
    _session
      ..removeListener(_onSessionChanged)
      ..dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final draft = _session.draft;
    if (_session.phase == ScribeSessionPhase.done && draft != null) {
      _close(draft);
    }
  }

  void _close([ConsultationNote? draft]) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(context, draft);
  }

  /// Close button / back gesture: confirm before losing a recording.
  Future<void> _requestClose() async {
    if (_session.phase == ScribeSessionPhase.processing) {
      final leave = await showScribeConfirmDialog(
        context,
        palette: _palette,
        icon: Icons.hourglass_top_rounded,
        title: 'Still creating the draft',
        message:
            "If you close now and it finishes, the draft is saved and "
            "you can review it the next time you open AI Voice Scribe for "
            "this visit.",
        confirmLabel: 'Close anyway',
        cancelLabel: 'Wait',
        destructive: false,
      );
      if (leave) _close();
      return;
    }
    if (_session.hasUnsavedAudio) {
      final discard = await _confirmDiscard();
      if (!discard) return;
      await _session.discardRecording();
    }
    _close();
  }

  Future<bool> _confirmDiscard() {
    return showScribeConfirmDialog(
      context,
      palette: _palette,
      icon: Icons.delete_outline_rounded,
      title: 'Discard recording?',
      message: 'The recording will be deleted and no note will be created.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep',
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
        final canPopFreely = !_session.isBusy && !_session.hasUnsavedAudio;
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
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _palette.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.mic_rounded, color: _palette.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Voice Scribe',
                style: AppColors.sectionHeading.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.label,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (token != null) 'Token $token',
                  patientName,
                  when,
                ].join(' · '),
                style: TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  color: c.label2,
                  fontSize: 12,
                  fontFeatures: CruType.tabular,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          icon: Icon(Icons.close_rounded, color: c.label2),
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
            palette: _palette,
            onDiscard: _discardRecording,
          ),
        );
      case ScribeSessionPhase.processing:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: ScribeProcessingPanel(controller: _session, palette: _palette),
        );
      case ScribeSessionPhase.failed:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ScribeFailurePanel(
            controller: _session,
            palette: _palette,
            onDiscard: _discardRecording,
          ),
        );
    }
  }

  Widget _buildReady() {
    if (widget.startedFromQueue && _session.pendingDraft == null) {
      return _buildQueueReady();
    }
    final c = context.cru;
    final pending = _session.pendingDraft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending != null) ...[
          ScribePendingDraftNotice(
            createdAt: pending.createdAt,
            palette: _palette,
            onReview: _session.resumePendingDraft,
          ),
          const SizedBox(height: 20),
        ],
        ScribeStepsStrip(palette: _palette),
        const SizedBox(height: 24),
        Text('PATIENT CONSENT', style: _palette.sectionLabel),
        const SizedBox(height: 10),
        ScribeConsentCard(
          value: _session.consentGiven,
          onChanged: _session.setConsent,
          palette: _palette,
        ),
        if (_session.error != null) ...[
          const SizedBox(height: 14),
          ScribeNotice(
            icon: Icons.error_outline_rounded,
            color: _palette.danger,
            background: _palette.dangerSoft,
            message: _session.error!,
          ),
        ],
        const SizedBox(height: 20),
        ScribePrimaryButton(
          label: 'Start recording',
          icon: Icons.mic_rounded,
          color: _palette.primary,
          onPressed: _session.consentGiven ? _session.start : null,
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _session.startManualNote,
          style: TextButton.styleFrom(
            foregroundColor: c.label2,
            textStyle: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Write the note without recording'),
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
        Text('BEFORE YOU BEGIN', style: _palette.sectionLabel),
        const SizedBox(height: 10),
        Text(
          'Ask the patient if this consultation can be recorded. The audio is '
          'only used to draft the session note and is deleted from this '
          'device once the draft is ready.',
          style: TextStyle(
            fontFamily: AppColors.bodyFontFamily,
            fontSize: 13.5,
            height: 1.4,
            color: c.label2,
          ),
        ),
        if (_session.error != null) ...[
          const SizedBox(height: 14),
          ScribeNotice(
            icon: Icons.error_outline_rounded,
            color: _palette.danger,
            background: _palette.dangerSoft,
            message: _session.error!,
          ),
        ],
        const SizedBox(height: 20),
        ScribePrimaryButton(
          label: 'Patient agreed — start recording',
          icon: Icons.mic_rounded,
          color: _palette.primary,
          onPressed: _session.consentAndStart,
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _session.startManualNote,
          style: TextButton.styleFrom(
            foregroundColor: c.label2,
            textStyle: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Patient declined — write the note myself'),
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
