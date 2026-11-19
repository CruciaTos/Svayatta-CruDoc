import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_session_note.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_potency_chips.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_remedy_field.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Same wording the case sheet uses for the direction of cure.
const _heringOptions = [
  'Inside-outward (Center to periphery)',
  'Above-downward (Head to limbs)',
  'Reverse order of symptoms',
  'Disorderly / Outward to inward (Suppression warning)',
];

/// One vertical strip of a patient's follow-up visits, newest first, built
/// only from the saved session notes: remedy given, response to the last
/// remedy and direction of cure. "Log follow-up" adds a note; each row can
/// be deleted.
class HomeopathyFollowUpTimeline extends ConsumerWidget {
  const HomeopathyFollowUpTimeline({super.key, required this.patientId});

  final String patientId;

  Future<void> _log(BuildContext context, WidgetRef ref) async {
    final sheet = ref.read(homeopathyCaseSheetProvider(patientId)).value;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.cru.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      builder: (_) => _LogFollowUpSheet(
        patientId: patientId,
        initialRemedy: sheet?.prescriptionNotes.prescribedRemedy ?? '',
        initialPotency: sheet?.prescriptionNotes.potency ?? '',
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    HomeopathySessionNote note,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Delete this follow-up?',
        leading: const CruIconTile(
          icon: CruIcons.warning,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Delete',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            'The ${DateFormat('d MMM yyyy').format(note.sessionDate)} entry '
            'is removed from the timeline.',
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
      ),
    );
    if (confirm == true) {
      await ref
          .read(homeopathySessionNotesRepositoryProvider)
          .deleteSessionNote(note.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final notes = [
      ...(ref.watch(homeopathySessionHistoryProvider(patientId)).value ??
          const <HomeopathySessionNote>[]),
    ]..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Follow-up timeline',
                  style: CruType.headline.tint(c.label),
                ),
              ),
              CruPressable(
                onTap: () => _log(context, ref),
                semanticLabel: 'Log follow-up',
                builder: (context, hovered) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruIcon(CruIcons.plus, size: CruSpace.s16, color: c.accent),
                    const SizedBox(width: CruSpace.s4),
                    Text(
                      'Log follow-up',
                      style: CruType.subhead.w600.tint(c.accentText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          if (notes.isEmpty)
            Text('No follow-up notes yet.', style: CruType.text.tint(c.label2))
          else ...[
            Text(
              _summary(notes),
              style: CruType.caption.tabular.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s12),
            for (var i = 0; i < notes.length; i++)
              _VisitRow(
                note: notes[i],
                last: i == notes.length - 1,
                onDelete: () => _delete(context, ref, notes[i]),
              ),
          ],
        ],
      ),
    );
  }

  static String? _response(HomeopathySessionNote n) {
    if (n.responseToRemedy != HomeopathyRemedyResponse.notApplicable) {
      return n.responseToRemedy.label;
    }
    if (n.symptomStatus != HomeopathySymptomStatus.unspecified) {
      return n.symptomStatus.label;
    }
    return null;
  }

  static String _summary(List<HomeopathySessionNote> notes) {
    final parts = <String>[
      notes.length == 1 ? '1 visit' : '${notes.length} visits',
    ];
    final response = _response(notes.first);
    if (response != null) parts.add('last: ${response.toLowerCase()}');
    for (final n in notes) {
      final d = n.heringsLawObservation.trim();
      if (d.isNotEmpty) {
        parts.add('direction: ${d.toLowerCase()}');
        break;
      }
    }
    return parts.join(' · ');
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({
    required this.note,
    required this.last,
    required this.onDelete,
  });

  final HomeopathySessionNote note;
  final bool last;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final remedy = [
      note.remedyGiven.trim(),
      note.potency.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    final response = HomeopathyFollowUpTimeline._response(note);
    final hering = note.heringsLawObservation.trim();
    final text = note.problemToday.trim();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: CruSpace.s20,
            child: Column(
              children: [
                const SizedBox(height: CruSpace.s4),
                Container(
                  width: CruSpace.s8,
                  height: CruSpace.s8,
                  decoration: BoxDecoration(
                    color: c.label3,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(child: Container(width: 1, color: c.separator)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : CruSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('d MMM yyyy').format(note.sessionDate),
                    style: CruType.callout.w600.tabular.tint(c.label),
                  ),
                  if (remedy.isNotEmpty) ...[
                    const SizedBox(height: CruSpace.s2),
                    Text('Rx: $remedy', style: CruType.text.tint(c.label)),
                  ],
                  if (response != null) ...[
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      'Response: $response',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                  if (hering.isNotEmpty) ...[
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      'Direction: $hering',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: CruSpace.s2),
                    Text(text, style: CruType.caption.tint(c.label2)),
                  ],
                ],
              ),
            ),
          ),
          CruIconButton(
            icon: FileIcons.trash,
            iconSize: 16,
            onPressed: onDelete,
            semanticLabel: 'Delete follow-up',
          ),
        ],
      ),
    );
  }
}

class _LogFollowUpSheet extends ConsumerStatefulWidget {
  const _LogFollowUpSheet({
    required this.patientId,
    required this.initialRemedy,
    required this.initialPotency,
  });

  final String patientId;
  final String initialRemedy;
  final String initialPotency;

  @override
  ConsumerState<_LogFollowUpSheet> createState() => _LogFollowUpSheetState();
}

class _LogFollowUpSheetState extends ConsumerState<_LogFollowUpSheet> {
  late final _remedy = TextEditingController(text: widget.initialRemedy);
  late final _potency = TextEditingController(text: widget.initialPotency);
  final _note = TextEditingController();
  HomeopathyRemedyResponse? _response;
  String _hering = '';
  bool _saving = false;

  @override
  void dispose() {
    _remedy.dispose();
    _potency.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    // Nothing entered: close instead of saving an empty visit.
    if (_note.text.trim().isEmpty &&
        _remedy.text.trim().isEmpty &&
        _response == null &&
        _hering.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    await ref
        .read(homeopathySessionNotesRepositoryProvider)
        .saveSessionNote(
          HomeopathySessionNote(
            id: const Uuid().v4(),
            patientId: widget.patientId,
            doctorId: '',
            sessionDate: now,
            problemToday: _note.text.trim(),
            responseToRemedy:
                _response ?? HomeopathyRemedyResponse.notApplicable,
            heringsLawObservation: _hering,
            remedyGiven: _remedy.text.trim(),
            potency: _potency.text.trim(),
            createdAt: now,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: EdgeInsets.only(
        left: CruSpace.s20,
        right: CruSpace.s20,
        top: CruSpace.s14,
        bottom: MediaQuery.of(context).viewInsets.bottom + CruSpace.s20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: CruSpace.s32 + CruSpace.s12,
                height: CruSpace.s4,
                margin: const EdgeInsets.only(bottom: CruSpace.s16),
                decoration: ShapeDecoration(
                  color: c.track,
                  shape: cruShape(CruRadius.full),
                ),
              ),
            ),
            Text('Log follow-up', style: CruType.title2.tint(c.label)),
            const SizedBox(height: CruSpace.s16),
            const HomeopathyGroupLabel('Response to previous remedy'),
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in HomeopathyRemedyResponse.values)
                  if (r != HomeopathyRemedyResponse.notApplicable)
                    HomeopathyChoiceChip(
                      label: r.label,
                      selected: _response == r,
                      onSelected: (sel) =>
                          setState(() => _response = sel ? r : null),
                    ),
              ],
            ),
            const SizedBox(height: CruSpace.s14),
            const HomeopathyGroupLabel('Direction of cure'),
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final h in _heringOptions)
                  HomeopathyChoiceChip(
                    label: h,
                    selected: _hering == h,
                    onSelected: (sel) => setState(() => _hering = sel ? h : ''),
                  ),
              ],
            ),
            const SizedBox(height: CruSpace.s14),
            HomeopathyRemedyField(
              controller: _remedy,
              label: 'Remedy given',
              hint: 'Leave empty if none',
            ),
            const SizedBox(height: CruSpace.s12),
            HomeopathyPotencyChips(controller: _potency),
            const SizedBox(height: CruSpace.s12),
            HomeopathyFormField(
              controller: _note,
              label: 'Note',
              hint: 'How the patient is today',
              maxLines: 3,
            ),
            const SizedBox(height: CruSpace.s16),
            CruButton(label: 'Save', expand: true, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
