import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/repo/consultation_note_repository.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_draft_form_controller.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_draft_form.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_palette.dart';
import 'package:doctor_management_app/features/scribe/presentation/widgets/scribe_recorder_widgets.dart';
import 'package:doctor_management_app/features/shell/components/shell_background.dart';

/// Full-screen review of a draft consultation note (mobile).
///
/// Every field is editable. Confirm stays disabled until the doctor ticks
/// "I've checked this note", so a draft can't be approved at a glance.
/// Confirm calls [ConsultationNoteRepository.confirmNote] (writes the
/// patient record and visit); Discard calls
/// [ConsultationNoteRepository.discardNote] (no patient-record changes).
///
/// Pops with true when confirmed, false otherwise.
class ScribeDraftReviewScreen extends ConsumerStatefulWidget {
  final ConsultationNote note;
  final Patient? patient;

  const ScribeDraftReviewScreen({super.key, required this.note, this.patient});

  @override
  ConsumerState<ScribeDraftReviewScreen> createState() =>
      _ScribeDraftReviewScreenState();
}

class _ScribeDraftReviewScreenState
    extends ConsumerState<ScribeDraftReviewScreen> {
  static const _palette = ScribePalette.mobile;

  late final ScribeDraftFormController _form = ScribeDraftFormController(
    widget.note,
  );
  bool _busy = false;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  bool get _isBlankManualNote =>
      _form.isEmpty && widget.note.transcript.trim().isEmpty;

  // ---- Actions ----

  Future<void> _confirm() async {
    if (_busy || !_form.canConfirm) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref
          .read(consultationNoteRepositoryProvider)
          .confirmNote(_form.toNote());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note saved to the patient record.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save the note: $e')));
    }
  }

  Future<void> _discard() async {
    final ok = await showScribeConfirmDialog(
      context,
      palette: _palette,
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
          .discardNote(widget.note);
    } catch (_) {
      // Leaving is still correct — the draft simply stays unreviewed.
    }
    if (mounted) Navigator.pop(context, false);
  }

  /// Back button: nothing reaches the patient record, but offer to keep
  /// the draft (with edits) so it can be finished later.
  Future<void> _leave() async {
    if (_busy) return;
    if (_isBlankManualNote) {
      Navigator.pop(context, false);
      return;
    }
    final save = await showScribeConfirmDialog(
      context,
      palette: _palette,
      icon: Icons.pending_actions_rounded,
      title: 'Finish later?',
      message:
          "The draft is kept on this device but isn't added to the "
          'patient record. Reopen AI Voice Scribe for this visit to finish '
          'reviewing it.',
      confirmLabel: 'Save draft & leave',
      cancelLabel: 'Keep reviewing',
      destructive: false,
    );
    if (!save || !mounted) return;
    try {
      await ref
          .read(consultationNoteRepositoryProvider)
          .saveNote(_form.toNote());
    } catch (_) {}
    if (mounted) Navigator.pop(context, false);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ShellBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      ScribeDraftForm(
                        controller: _form,
                        palette: _palette,
                        existingDiagnoses:
                            widget.patient?.diagnosis ?? const [],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildTopBar() {
    final patientName = widget.patient?.fullName ?? 'Unknown patient';
    final when = DateFormat('d MMM yyyy').format(widget.note.createdAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onPressed: _leave,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review Note',
                  style: AppColors.pageHeading.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$patientName · $when',
                  style: AppColors.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _palette.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _palette.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              'Draft',
              style: AppColors.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: _palette.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return ListenableBuilder(
      listenable: _form,
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _busy ? null : () => _form.setReviewed(!_form.reviewed),
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    Checkbox(
                      value: _form.reviewed,
                      onChanged: _busy
                          ? null
                          : (v) => _form.setReviewed(v ?? false),
                      activeColor: _palette.primary,
                      side: BorderSide(color: _palette.hint, width: 1.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _form.reviewed && _form.isEmpty
                            ? 'Add at least one detail to save the note'
                            : "I've checked this note against the consultation",
                        style: AppColors.bodyMeta.copyWith(
                          color: _form.reviewed && _form.isEmpty
                              ? _palette.warning
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _discard,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Discard'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _palette.danger,
                        side: BorderSide(
                          color: _palette.danger.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_busy || !_form.canConfirm) ? null : _confirm,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Confirm & Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _palette.success,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _palette.success.withValues(
                          alpha: 0.35,
                        ),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
