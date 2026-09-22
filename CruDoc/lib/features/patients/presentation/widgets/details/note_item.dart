import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// One clinical note: "Today · Surgical exposure" + time, the note text,
/// and (for a visit with a confirmed Scribe note) the violet Scribe tag.
class NoteItem extends StatelessWidget {
  const NoteItem({
    super.key,
    required this.heading,
    required this.body,
    this.trailing,
    this.visitId,
  });

  final String heading;
  final String body;

  /// Time (or "On file"), quiet and tabular.
  final String? trailing;

  /// When set, shows the Scribe tag if that visit has a confirmed
  /// Scribe note.
  final String? visitId;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: CruType.subhead.w600.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: CruSpace.s12),
                Text(trailing!, style: CruType.caption.tabular.tint(c.label3)),
              ],
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          Text(body, style: CruType.note.tint(c.label)),
          if (visitId != null) ScribeTag(visitId: visitId!),
        ],
      ),
    );
  }
}

/// "✦ Dictated with Scribe · reviewed by Dr. Deshpande" in AI violet.
/// Shown only when the visit has a confirmed Scribe note; the reviewer
/// part is dropped when the doctor's name isn't known.
class ScribeTag extends ConsumerWidget {
  const ScribeTag({super.key, required this.visitId});
  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesForVisitProvider(visitId)).value;
    final confirmed = notes?.any(
          (n) => n.status == ConsultationNoteStatus.confirmed,
        ) ??
        false;
    if (!confirmed) return const SizedBox.shrink();
    final doctor = ref.watch(doctorIdentityProvider).greetingName;
    final c = context.cru;
    final text = doctor == null
        ? 'Dictated with Scribe'
        : 'Dictated with Scribe · reviewed by $doctor';
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s6),
      child: Row(
        children: [
          CruIcon(CruIcons.sparkleSingle, size: 13, strokeWidth: 2, color: c.ai),
          const SizedBox(width: CruSpace.s6),
          Flexible(
            child: Text(
              text,
              style: CruType.groupLabel.w500.tint(c.ai),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
