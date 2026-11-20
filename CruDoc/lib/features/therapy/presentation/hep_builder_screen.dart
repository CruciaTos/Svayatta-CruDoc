import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/hep_template_picker.dart';
import 'package:doctor_management_app/features/therapy/presentation/exercise_library_screen.dart';
import 'package:doctor_management_app/features/therapy/presentation/hep_share.dart';
import 'package:doctor_management_app/features/therapy/presentation/protocol_picker.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Builds or edits a patient's home exercise program (record kind
/// `physioHep`). Pass [program] to edit, or leave it null for a new one.
class HepBuilderScreen extends ConsumerStatefulWidget {
  const HepBuilderScreen({super.key, required this.patient, this.program});

  final Patient patient;
  final HepProgram? program;

  @override
  ConsumerState<HepBuilderScreen> createState() => _HepBuilderScreenState();
}

class _HepBuilderScreenState extends ConsumerState<HepBuilderScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.program?.title.isNotEmpty == true
        ? widget.program!.title
        : 'Home exercise program',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.program?.note ?? '',
  );
  late final List<HepItem> _items = [...?widget.program?.items];
  HepProgram? _saved;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.program;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final picked = await Navigator.of(context).push<List<ExerciseDef>>(
      MaterialPageRoute(
        builder: (_) => const ExerciseLibraryScreen(picking: true),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final e in picked) {
        if (!_items.any((i) => i.exerciseId == e.id)) {
          _items.add(HepItem.fromExercise(e));
        }
      }
    });
  }

  Future<void> _startFromProtocol() async {
    final proto = await pickRehabProtocol(context);
    if (proto == null || !mounted) return;
    final items = protocolItems(proto, ref.read(exerciseCatalogProvider));
    setState(() {
      for (final i in items) {
        if (!_items.any((x) => x.exerciseId == i.exerciseId)) _items.add(i);
      }
    });
  }

  Future<void> _startFromTemplate() async {
    final t = await pickHepTemplate(context);
    if (t == null || !mounted) return;
    setState(() {
      for (final i in t.items) {
        if (!_items.any((x) => x.exerciseId == i.exerciseId)) _items.add(i);
      }
      // A programme built from a saved one takes its name, unless the physio
      // has already typed their own.
      if (_title.text.trim().isEmpty ||
          _title.text.trim() == 'Home exercise program') {
        _title.text = t.title;
      }
    });
  }

  /// Keeps the current exercises as a programme the clinic can reuse.
  ///
  /// Only the title and the exercises are kept. The note is left behind
  /// because it was written about this patient, and the template belongs to
  /// no patient at all.
  Future<void> _saveAsTemplate() async {
    if (_items.isEmpty) {
      recToast(context, 'Add at least one exercise');
      return;
    }
    final title = _title.text.trim();
    await saveDentalRecord(
      ref,
      DentalRecord.create(
        '',
        RecKind.physioHepTemplate,
        HepTemplate.toData(
          title: title.isEmpty ? 'Saved program' : title,
          items: _items,
        ),
      ),
    );
    if (mounted) recToast(context, 'Saved to your programs');
  }

  /// Saves the program and returns it (new record, or the same one updated).
  Future<HepProgram?> _save() async {
    if (_items.isEmpty) {
      recToast(context, 'Add at least one exercise');
      return null;
    }
    final data = HepProgram.toData(
      title: _title.text.trim(),
      note: _note.text.trim(),
      items: _items,
    );
    final existing = _saved?.record;
    final record = existing != null
        ? existing.copyWith(data: data)
        : DentalRecord.create(widget.patient.id, RecKind.physioHep, data);
    await saveDentalRecord(ref, record);
    return _saved = HepProgram.fromRecord(record);
  }

  Future<void> _saveAndClose() async {
    setState(() => _busy = true);
    final p = await _save();
    if (!mounted) return;
    setState(() => _busy = false);
    if (p != null) {
      recToast(context, 'Program saved');
      Navigator.of(context).pop();
    }
  }

  Future<void> _deleteProgram() async {
    final saved = _saved;
    if (saved == null) return;
    final ok = await confirmDental(
      context,
      title: 'Delete this program?',
      body:
          '"${saved.title.isEmpty ? 'Home exercise program' : saved.title}" and its ${saved.items.length} exercise${saved.items.length == 1 ? '' : 's'} will be removed.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    await deleteDentalRecord(ref, saved.record);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _share(bool whatsapp) async {
    setState(() => _busy = true);
    final p = await _save();
    if (!mounted) return;
    setState(() => _busy = false);
    if (p == null) return;
    final catalog = ref.read(exerciseCatalogProvider);
    final doctor = ref.read(doctorIdentityProvider).fullName;
    try {
      if (whatsapp) {
        await sendHepWhatsApp(
          context,
          patient: widget.patient,
          program: p,
          catalog: catalog,
          doctorName: doctor,
        );
      } else {
        await shareHepPdf(
          context,
          patient: widget.patient,
          program: p,
          catalog: catalog,
          doctorName: doctor,
        );
      }
    } catch (e) {
      debugPrint('share hep failed: $e');
      if (mounted) recToast(context, "Couldn't share. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: Text(widget.patient.fullName),
        actions: [
          if (_saved != null)
            IconButton(
              tooltip: 'Delete program',
              icon: Icon(Icons.delete_outline, color: c.label2),
              onPressed: _busy ? null : _deleteProgram,
            ),
          CruCapsuleButton(
            label: 'PDF',
            icon: CruIcons.fileText,
            onPressed: _busy ? null : () => _share(false),
          ),
          const SizedBox(width: CruSpace.s8),
          CruCapsuleButton(
            label: 'WhatsApp',
            icon: CruIcons.whatsapp,
            onPressed: _busy ? null : () => _share(true),
          ),
          const SizedBox(width: CruSpace.s12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s16),
              children: [
                CruTextField(label: 'Program name', controller: _title),
                const SizedBox(height: CruSpace.s16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'EXERCISES (${_items.length})',
                        style: CruType.micro.w600.tint(c.label2),
                      ),
                    ),
                    if (_items.isNotEmpty) ...[
                      CruCapsuleButton(
                        label: 'Save as template',
                        icon: CruIcons.check,
                        onPressed: _busy ? null : _saveAsTemplate,
                      ),
                      const SizedBox(width: CruSpace.s8),
                      CruCapsuleButton(
                        label: 'Protocol',
                        icon: CruIcons.fileText,
                        onPressed: _startFromProtocol,
                      ),
                      const SizedBox(width: CruSpace.s8),
                    ],
                    CruCapsuleButton(
                      label: 'Add exercise',
                      icon: CruIcons.plus,
                      onPressed: _add,
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s8),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: CruSpace.s24),
                    child: Column(
                      children: [
                        Text(
                          'Pick exercises from the library.',
                          style: CruType.caption.tint(c.label3),
                        ),
                        const SizedBox(height: CruSpace.s12),
                        CruCapsuleButton(
                          label: 'Start from a protocol',
                          icon: CruIcons.fileText,
                          onPressed: _startFromProtocol,
                        ),
                        const SizedBox(height: CruSpace.s8),
                        CruCapsuleButton(
                          label: 'Start from a saved program',
                          icon: CruIcons.fileText,
                          onPressed: _startFromTemplate,
                        ),
                      ],
                    ),
                  )
                else
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: true,
                    onReorderItem: (from, to) => setState(() {
                      _items.insert(to, _items.removeAt(from));
                    }),
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          key: ValueKey(_items[i].exerciseId),
                          padding: const EdgeInsets.only(bottom: CruSpace.s8),
                          child: _ItemCard(
                            item: _items[i],
                            onChanged: (v) => setState(() => _items[i] = v),
                            onRemove: () => setState(() => _items.removeAt(i)),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: CruSpace.s12),
                CruTextField(
                  label: 'Note for the patient',
                  controller: _note,
                  maxLines: 3,
                  optional: true,
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: CruButton(
                label: 'Save program',
                expand: true,
                onPressed: _busy ? null : _saveAndClose,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final HepItem item;
  final ValueChanged<HepItem> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name, style: CruType.body.w600.tint(c.label)),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.delete_outline, size: 20, color: c.label2),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s16,
            runSpacing: CruSpace.s8,
            children: [
              _Stepper(
                label: 'Sets',
                value: item.sets,
                min: 1,
                onChanged: (v) => onChanged(item.copyWith(sets: v)),
              ),
              _Stepper(
                label: 'Reps',
                value: item.reps,
                min: 1,
                onChanged: (v) => onChanged(item.copyWith(reps: v)),
              ),
              _Stepper(
                label: 'Hold (s)',
                value: item.holdSeconds,
                min: 0,
                step: 5,
                onChanged: (v) => onChanged(item.copyWith(holdSeconds: v)),
              ),
              _Stepper(
                label: 'Per day',
                value: item.perDay,
                min: 1,
                onChanged: (v) => onChanged(item.copyWith(perDay: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: CruType.micro.tint(c.label2)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: value - step >= min
                  ? () => onChanged(value - step)
                  : null,
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: CruType.body.w600
                    .tint(c.label)
                    .copyWith(fontFeatures: CruType.tabular),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => onChanged(value + step),
            ),
          ],
        ),
      ],
    );
  }
}
