// desktop_scribe_screen.dart
//
// Full-panel AI Voice Scribe screen for the desktop shell.
//
// Rendered as a SizedBox.expand content-area widget with the same glass
// container and header as DesktopQueueScreen / DesktopEventsScreen, so the
// sidebar stays visible throughout the recording → review flow.
//
// Layout:
//   • Session: today's visits on the left, the selected visit's consent /
//     recording / processing panel on the right.
//   • Review: the editable draft (shared ScribeDraftForm) with an action bar.
//
// Recording and processing are driven by ScribeSessionController — the same
// state machine the mobile sheet uses. Nothing is written to the patient
// record until the doctor confirms the reviewed draft.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_form_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_session_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_draft_form.dart';
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
  ScribeDraftFormController? _form;
  bool _busy = false;

  @override
  void dispose() {
    _disposeSession();
    _form?.dispose();
    super.dispose();
  }

  // ---- Session lifecycle ----

  /// Switching visits would drop an in-progress or kept recording.
  bool get _sessionLocked =>
      (_session?.isBusy ?? false) || (_session?.hasUnsavedAudio ?? false);

  void _selectVisit(Visit visit, Patient? patient) {
    if (_sessionLocked) return;
    if (_visit?.id == visit.id) return;
    _disposeSession();
    final session = ScribeSessionController(
      visit: visit,
      processingService: ref.read(scribeProcessingServiceProvider),
      repository: ref.read(consultationNoteRepositoryProvider),
    )..addListener(_onSessionChanged);
    session.loadPendingDraft();
    setState(() {
      _visit = visit;
      _patient = patient;
      _session = session;
    });
  }

  void _onSessionChanged() {
    final session = _session;
    final draft = session?.draft;
    if (session?.phase == ScribeSessionPhase.done &&
        draft != null &&
        _form == null) {
      setState(() => _form = ScribeDraftFormController(draft));
    }
  }

  void _disposeSession() {
    _session
      ?..removeListener(_onSessionChanged)
      ..dispose();
    _session = null;
  }

  void _resetToIdle() {
    final form = _form;
    _disposeSession();
    setState(() {
      _form = null;
      _visit = null;
      _patient = null;
      _busy = false;
    });
    // Dispose after the review fields have been unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => form?.dispose());
  }

  Future<void> _discardRecording() async {
    final ok = await showScribeConfirmDialog(
      context,
      palette: _p,
      icon: Icons.delete_outline_rounded,
      title: 'Discard recording?',
      message: 'The recording will be deleted and no note will be created.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep',
    );
    if (ok) await _session?.discardRecording();
  }

  // ---- Review actions ----

  Future<void> _confirmNote() async {
    final form = _form;
    if (_busy || form == null || !form.canConfirm) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(consultationNoteRepositoryProvider)
          .confirmNote(form.toNote());
      if (!mounted) return;
      _showSnack(
        'Note saved to ${_patient?.fullName ?? 'the patient'}’s record.',
      );
      _resetToIdle();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('Could not save the note: $e', isError: true);
    }
  }

  Future<void> _discardNote() async {
    final form = _form;
    if (form == null) return;
    final ok = await showScribeConfirmDialog(
      context,
      palette: _p,
      icon: Icons.delete_outline_rounded,
      title: 'Discard this note?',
      message:
          'The draft will be deleted. Nothing is added to the patient '
          'record.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep reviewing',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(consultationNoteRepositoryProvider)
          .discardNote(form.original);
    } catch (_) {}
    if (mounted) _resetToIdle();
  }

  Future<void> _saveForLater() async {
    final form = _form;
    if (form == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (!(form.isEmpty && form.original.transcript.trim().isEmpty)) {
        await ref
            .read(consultationNoteRepositoryProvider)
            .saveNote(form.toNote());
        if (mounted) {
          _showSnack('Draft saved. Select the visit again to finish it.');
        }
      }
    } catch (_) {}
    if (mounted) _resetToIdle();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _p.danger : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final reviewing = _form != null;
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
                  reviewing ? _buildReviewHeader() : _buildSessionHeader(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: reviewing ? _buildReviewBody() : _buildSessionBody(),
                  ),
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
      subtitle: 'Record a consultation and get a draft clinical note to review',
      pill: DateFormat('EEEE, MMM d').format(DateTime.now()),
    );
  }

  Widget _buildReviewHeader() {
    final form = _form!;
    return _PageHeader(
      icon: Icons.fact_check_outlined,
      title: 'Review Clinical Note',
      subtitle:
          '${_patient?.fullName ?? 'Unknown patient'} · '
          '${DateFormat('d MMM yyyy, h:mm a').format(form.original.createdAt)}',
      pill: 'Draft',
      pillColor: _p.warning,
    );
  }

  // ---- Session (visit picker + recorder) ----

  Widget _buildSessionBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildVisitList(scrollable: true)),
              const SizedBox(width: 20),
              SizedBox(width: 420, child: _buildSessionPanel(expand: true)),
            ],
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
                Text("TODAY'S VISITS", style: _p.sectionLabel),
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
                const Spacer(),
                if (locked)
                  Text(
                    'Finish or discard the current recording to switch',
                    style: TextStyle(fontSize: 11.5, color: _p.hint),
                  ),
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
          ScribeSessionPhase.ready ||
          ScribeSessionPhase.done => _buildReadyPanel(session),
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
        final centred = session.phase != ScribeSessionPhase.ready;

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

  Widget _buildReadyPanel(ScribeSessionController session) {
    final pending = session.pendingDraft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending != null) ...[
          ScribePendingDraftNotice(
            createdAt: pending.createdAt,
            palette: _p,
            onReview: session.resumePendingDraft,
          ),
          const SizedBox(height: 20),
        ],
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
        const SizedBox(height: 6),
        TextButton(
          onPressed: session.startManualNote,
          style: TextButton.styleFrom(
            foregroundColor: _p.textSecondary,
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

  // ---- Review ----

  Widget _buildReviewBody() {
    final form = _form!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: ScribeDraftForm(
              controller: form,
              palette: _p,
              existingDiagnoses: _patient?.diagnosis ?? const [],
            ),
          ),
        ),
        ListenableBuilder(
          listenable: form,
          builder: (context, _) => _Card(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            child: Row(
              children: [
                Checkbox(
                  value: form.reviewed,
                  onChanged: _busy ? null : (v) => form.setReviewed(v ?? false),
                  activeColor: _p.primary,
                  side: BorderSide(color: _p.hint, width: 1.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _busy
                        ? null
                        : () => form.setReviewed(!form.reviewed),
                    child: Text(
                      form.reviewed && form.isEmpty
                          ? 'Add at least one detail to save the note'
                          : "I've checked this note against the consultation",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: form.reviewed && form.isEmpty
                            ? _p.warning
                            : _p.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _busy ? null : _saveForLater,
                  style: TextButton.styleFrom(
                    foregroundColor: _p.textSecondary,
                  ),
                  child: const Text('Finish later'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _discardNote,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Discard'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _p.danger,
                    side: BorderSide(color: _p.danger.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: (_busy || !form.canConfirm) ? null : _confirmNote,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                  label: const Text('Confirm & save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _p.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    this.pillColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? pill;
  final Color? pillColor;

  @override
  Widget build(BuildContext context) {
    final tint = pillColor;
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
                        color: tint?.withValues(alpha: 0.12) ?? _p.field,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: tint?.withValues(alpha: 0.4) ?? _p.border,
                        ),
                      ),
                      child: Text(
                        pill!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tint ?? _p.textSecondary,
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
