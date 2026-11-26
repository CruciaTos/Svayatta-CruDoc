import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/scribe/data/models/physio_findings.dart';
import 'package:doctor_management_app/features/therapy/data/physio_providers.dart';
import 'package:doctor_management_app/features/therapy/data/soap_phrases.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Quick-tap phrases under the session note: one tap puts a standard
/// sentence into the note instead of typing it again.
///
/// Physiotherapy-only, because the phrases are physiotherapy wording — it
/// takes no room at all for every other specialty. Collapsed by default: the
/// note is the thing being written, and forty chips above it would bury it.
/// One section is open at a time, which is the whole list a physio needs at
/// any one moment in a session.
///
/// A phrase with a gap in it (see [blank]) leaves the caret on the gap, so
/// the note reads as unfinished until a real value is typed. Nothing here
/// ever writes a number.
class SoapPhraseBar extends ConsumerStatefulWidget {
  const SoapPhraseBar({
    super.key,
    required this.controller,
    required this.patientId,
    this.enabled = true,
  });

  /// The note being written. Phrases are inserted at its caret.
  final TextEditingController controller;
  final String patientId;
  final bool enabled;

  @override
  ConsumerState<SoapPhraseBar> createState() => _SoapPhraseBarState();
}

class _SoapPhraseBarState extends ConsumerState<SoapPhraseBar> {
  /// The open section, or null while the bar is collapsed.
  SoapSection? _open;

  void _insert(SoapPhrase phrase) {
    final c = widget.controller;
    final result = insertSoapPhrase(
      c.text,
      c.selection.isValid ? c.selection.start : -1,
      phrase,
    );
    // Set text and caret together: assigning `text` alone drops the caret to
    // the end, which would undo the point of landing it on the gap.
    c.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.caret),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clinical = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalView),
    );
    final show =
        clinical &&
        (ref.watch(isPhysiotherapyProvider) ||
            ref.watch(patientHasPhysioProvider(widget.patientId)));
    if (!show) return const SizedBox.shrink();
    final c = context.cru;
    final open = _open;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('QUICK PHRASES', style: CruType.groupLabel.tint(c.label2)),
            const Spacer(),
            for (final s in SoapSection.values)
              Padding(
                padding: const EdgeInsets.only(left: CruSpace.s8),
                child: DentalChoiceChip(
                  label: s.letter,
                  selected: open == s,
                  // Tapping the open section closes it, so the chips can be
                  // got out of the way without hunting for a close button.
                  onTap: widget.enabled
                      ? () => setState(() => _open = open == s ? null : s)
                      : () {},
                ),
              ),
          ],
        ),
        if (open != null) ...[
          const SizedBox(height: CruSpace.s8),
          Text(open.title, style: CruType.caption.tint(c.label3)),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final p in soapPhrasesOf(open))
                _PhraseChip(
                  phrase: p,
                  enabled: widget.enabled,
                  onTap: () => _insert(p),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One phrase. Not a [DentalChoiceChip]: these are actions, not a choice
/// that stays selected, and a chip that latched on would read as a finding
/// already in the note.
class _PhraseChip extends StatelessWidget {
  const _PhraseChip({
    required this.phrase,
    required this.enabled,
    required this.onTap,
  });

  final SoapPhrase phrase;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      button: true,
      label: phrase.hasBlank ? '${phrase.text}, fill in the gap' : phrase.text,
      child: Material(
        color: c.inset,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: CruSpace.s8,
            ),
            child: Text(
              phrase.label,
              style: CruType.caption.tint(enabled ? c.label : c.label3),
            ),
          ),
        ),
      ),
    );
  }
}
