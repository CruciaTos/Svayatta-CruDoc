import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Add a note for today's visit": one line that grows while focused.
/// Ctrl+Enter saves to today's visit, or to the patient's note on file
/// (dated) when there is no visit today. The violet mic opens Scribe.
class NoteComposer extends ConsumerStatefulWidget {
  const NoteComposer({super.key, required this.summary, required this.now});

  final PatientSummary summary;
  final DateTime now;

  @override
  ConsumerState<NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends ConsumerState<NoteComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Note composer');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    _controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    _controller.removeListener(_rebuild);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final s = widget.summary;
    final visit = PatientActions.todaysVisit(s, widget.now);
    setState(() => _saving = true);
    try {
      if (visit != null) {
        final existing = visit.therapistNotes?.trim() ?? '';
        await ref.read(visitRepositoryProvider).updateVisit(visit.id, {
          'therapistNotes': existing.isEmpty ? text : '$existing\n$text',
        });
      } else {
        final existing = s.patient.notes.trim();
        final dated = '[${DateFormat('d MMM y').format(widget.now)}] $text';
        await ref.read(patientRepositoryProvider).updateDoctorsNote(
              s.id,
              existing.isEmpty ? dated : '$existing\n$dated',
            );
      }
      _controller.clear();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text("Couldn't save the note: $e"),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final focused = _focus.hasFocus;
    final hasText = _controller.text.trim().isNotEmpty;
    return AnimatedSize(
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(minHeight: CruSize.composer),
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          CruSpace.s6,
          CruSpace.s6,
          CruSpace.s6,
        ),
        decoration: ShapeDecoration(
          color: c.inset,
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): _save,
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    readOnly: _saving,
                    minLines: 1,
                    maxLines: focused ? 6 : 1,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    cursorColor: c.accent,
                    style: CruType.input.tint(c.label),
                    decoration: InputDecoration.collapsed(
                      hintText: "Add a note for today's visit",
                      hintStyle: CruType.input.tint(c.label3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: CruSpace.s10),
            if (hasText) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: CruSpace.s4),
                child: CruCapsuleButton(
                  label: 'Save',
                  kind: CruCapsuleKind.surface,
                  height: CruSize.rowCapsule,
                  semanticLabel: 'Save note (Ctrl+Enter)',
                  onPressed: _saving ? null : _save,
                ),
              ),
              const SizedBox(width: CruSpace.s8),
            ],
            _MicButton(
              onPressed: () => PatientActions.dictate(
                context,
                widget.summary,
                widget.now,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 36 px surface button with a hairline ring; the mic is AI violet.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: 'Dictate with Scribe',
      tooltip: 'Dictate with Scribe',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        width: CruSize.squareButton,
        height: CruSize.squareButton,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: hovered ? c.aiTint : c.surface,
          shape: cruShape(
            CruRadius.iconTile,
            side: BorderSide(color: c.hairline),
          ),
          shadows: c.cardShadow,
        ),
        child: CruIcon(CruIcons.mic, size: 18, strokeWidth: 1.9, color: c.ai),
      ),
    );
  }
}
