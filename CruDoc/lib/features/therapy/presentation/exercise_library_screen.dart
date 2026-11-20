import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/exercise_visual.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Exercise library: search, region chips, tap for the detail page.
///
/// With [picking] true (opened from the program builder) the detail page has
/// "Add to program" and the screen pops with the chosen exercises.
class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key, this.picking = false});

  final bool picking;

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  final _search = TextEditingController();
  ExerciseRegion? _region;
  final List<ExerciseDef> _picked = [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(ExerciseDef e) async {
    final add = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExerciseDetailScreen(
          exerciseId: e.id,
          canAdd: widget.picking && !_picked.any((x) => x.id == e.id),
        ),
      ),
    );
    if (add == true && mounted) {
      final fresh = ref
          .read(exerciseCatalogProvider)
          .firstWhere((x) => x.id == e.id, orElse: () => e);
      setState(() => _picked.add(fresh));
    }
  }

  /// Stars or unstars [e]. The flag rides on the same `physioExercise`
  /// record that already carries this exercise's photo and video, so a
  /// starred exercise needs no record of its own.
  Future<void> _toggleFavourite(ExerciseDef e) async {
    final recs =
        ref.read(clinicRecordsProvider(RecKind.physioExercise)).value ??
        const <DentalRecord>[];
    final existing = recs
        .where((r) => r.str('exerciseId') == e.id && r.data['custom'] != true)
        .firstOrNull;
    final next = !e.favourite;
    final record = existing != null
        ? existing.copyWith(data: {...existing.data, 'favourite': next})
        : DentalRecord.create('', RecKind.physioExercise, {
            'exerciseId': e.id,
            'favourite': next,
          });
    await saveDentalRecord(ref, record);
  }

  Future<void> _addCustom() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const _CustomExerciseScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final all = orderExercises(
      ref.watch(exerciseCatalogProvider),
      ref.watch(recentExercisesProvider),
    );
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final e in all)
        if ((_region == null || e.region == _region) &&
            (q.isEmpty ||
                e.name.toLowerCase().contains(q) ||
                e.goal.toLowerCase().contains(q)))
          e,
    ];

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: const Text('Exercise library'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: CruSpace.s12),
            child: CruCapsuleButton(
              label: 'New exercise',
              icon: CruIcons.plus,
              onPressed: _addCustom,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s16,
              CruSpace.s8,
              CruSpace.s16,
              CruSpace.s8,
            ),
            child: CruTextField(
              label: 'Search',
              controller: _search,
              hint: 'Exercise or goal',
              icon: CruIcons.search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
              children: [
                DentalChoiceChip(
                  label: 'All',
                  selected: _region == null,
                  onTap: () => setState(() => _region = null),
                ),
                for (final r in ExerciseRegion.values) ...[
                  const SizedBox(width: CruSpace.s8),
                  DentalChoiceChip(
                    label: r.label,
                    selected: _region == r,
                    onTap: () => setState(() => _region = r),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      'No exercises match.',
                      style: CruType.caption.tint(c.label3),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(CruSpace.s16),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: CruSpace.s8),
                    itemBuilder: (_, i) {
                      final e = shown[i];
                      final added = _picked.any((x) => x.id == e.id);
                      return CruCard(
                        child: InkWell(
                          onTap: () => _open(e),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: c.inset,
                                  borderRadius: BorderRadius.circular(
                                    CruRadius.control,
                                  ),
                                ),
                                child: Icon(
                                  e.region.icon,
                                  size: 22,
                                  color: c.label2,
                                ),
                              ),
                              const SizedBox(width: CruSpace.s12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.name,
                                      style: CruType.body.w600.tint(c.label),
                                    ),
                                    const SizedBox(height: CruSpace.s2),
                                    Text(
                                      '${e.region.label} · ${e.level.label}'
                                      '${e.isCustom ? ' · Yours' : ''}'
                                      '${e.hasMedia ? ' · Has media' : ''}'
                                      '${e.favourite ? ' · Starred' : ''}',
                                      style: CruType.caption.tint(c.label2),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: e.favourite
                                    ? 'Remove star'
                                    : 'Star this exercise',
                                icon: Icon(
                                  e.favourite
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 20,
                                  color: e.favourite ? c.amberText : c.label3,
                                ),
                                onPressed: () => _toggleFavourite(e),
                              ),
                              if (added)
                                CruIcon(CruIcons.check, color: c.label2),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (widget.picking)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(CruSpace.s16),
                child: CruButton(
                  label: _picked.isEmpty
                      ? 'Done'
                      : 'Add ${_picked.length} to program',
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(_picked),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One exercise: visual area, steps and cautions. Pops `true` on
/// "Add to program" when [canAdd].
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exerciseId,
    this.canAdd = false,
  });

  final String exerciseId;
  final bool canAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final e = ref
        .watch(exerciseCatalogProvider)
        .where((x) => x.id == exerciseId)
        .firstOrNull;
    if (e == null) return const Scaffold(body: SizedBox.shrink());

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          if (e.isCustom && e.recordId != null)
            IconButton(
              tooltip: 'Delete exercise',
              icon: Icon(Icons.delete_outline, color: c.label2),
              onPressed: () async {
                final rec = (ref
                            .read(clinicRecordsProvider(RecKind.physioExercise))
                            .value ??
                        const <DentalRecord>[])
                    .where((r) => r.id == e.recordId)
                    .firstOrNull;
                if (rec == null) return;
                final ok = await confirmDental(
                  context,
                  title: 'Delete this exercise?',
                  body:
                      '"${e.name}" will be removed from your library. Programs already made keep their copy.',
                  action: 'Delete',
                );
                if (!ok) return;
                await deleteDentalRecord(ref, rec);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(CruSpace.s16),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ExerciseVisual(exercise: e, editable: true),
          ),
          const SizedBox(height: CruSpace.s16),
          Text(
            '${e.region.label} · ${e.level.label}',
            style: CruType.caption.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(e.goal, style: CruType.body.tint(c.label)),
          const SizedBox(height: CruSpace.s16),
          Text('HOW TO DO IT', style: CruType.micro.w600.tint(c.label2)),
          const SizedBox(height: CruSpace.s8),
          for (var i = 0; i < e.steps.length; i++) ...[
            CruCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.inset,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: CruType.caption.w600.tint(c.label),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(e.steps[i], style: CruType.body.tint(c.label)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s8),
          ],
          const SizedBox(height: CruSpace.s8),
          Text(
            'MISTAKES AND WHEN TO STOP',
            style: CruType.micro.w600.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s8),
          Text(e.cautions, style: CruType.body.tint(c.label)),
          const SizedBox(height: CruSpace.s16),
          Text(
            'Usual dose: ${HepItem.fromExercise(e).doseText}',
            style: CruType.caption.tint(c.label2),
          ),
          if (canAdd) ...[
            const SizedBox(height: CruSpace.s24),
            CruButton(
              label: 'Add to program',
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomExerciseScreen extends ConsumerStatefulWidget {
  const _CustomExerciseScreen();

  @override
  ConsumerState<_CustomExerciseScreen> createState() =>
      _CustomExerciseScreenState();
}

class _CustomExerciseScreenState extends ConsumerState<_CustomExerciseScreen> {
  final _name = TextEditingController();
  final _goal = TextEditingController();
  final _steps = TextEditingController();
  final _cautions = TextEditingController();
  final _sets = TextEditingController(text: '3');
  final _reps = TextEditingController(text: '10');
  final _hold = TextEditingController(text: '0');
  final _perDay = TextEditingController(text: '1');
  ExerciseRegion _region = ExerciseRegion.core;
  ExerciseLevel _level = ExerciseLevel.easy;
  bool _saving = false;

  @override
  void dispose() {
    for (final t in [
      _name,
      _goal,
      _steps,
      _cautions,
      _sets,
      _reps,
      _hold,
      _perDay,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  int _n(TextEditingController t, int fallback) =>
      int.tryParse(t.text.trim()) ?? fallback;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      recToast(context, 'Give the exercise a name');
      return;
    }
    setState(() => _saving = true);
    await saveCustomExercise(
      ref,
      name: name,
      region: _region,
      goal: _goal.text.trim(),
      steps: [
        for (final l in _steps.text.split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ],
      cautions: _cautions.text.trim(),
      sets: _n(_sets, 3),
      reps: _n(_reps, 10),
      holdSeconds: _n(_hold, 0),
      perDay: _n(_perDay, 1),
      level: _level,
    );
    if (mounted) {
      recToast(context, 'Exercise saved. Open it to add a photo or video.');
      Navigator.of(context).pop();
    }
  }

  Widget _num(String label, TextEditingController t) => Expanded(
    child: CruTextField(
      label: label,
      controller: t,
      keyboardType: TextInputType.number,
      tabular: true,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('New exercise')),
      body: ListView(
        padding: const EdgeInsets.all(CruSpace.s16),
        children: [
          CruTextField(label: 'Name', controller: _name, autofocus: true),
          const SizedBox(height: CruSpace.s12),
          Text('BODY REGION', style: CruType.micro.w600.tint(c.label2)),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final r in ExerciseRegion.values)
                DentalChoiceChip(
                  label: r.label,
                  selected: _region == r,
                  onTap: () => setState(() => _region = r),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          Text('DIFFICULTY', style: CruType.micro.w600.tint(c.label2)),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s8,
            children: [
              for (final l in ExerciseLevel.values)
                DentalChoiceChip(
                  label: l.label,
                  selected: _level == l,
                  onTap: () => setState(() => _level = l),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(label: 'Goal', controller: _goal, optional: true),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Steps (one per line)',
            controller: _steps,
            maxLines: 5,
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Mistakes and when to stop',
            controller: _cautions,
            maxLines: 2,
            optional: true,
          ),
          const SizedBox(height: CruSpace.s12),
          Row(
            children: [
              _num('Sets', _sets),
              const SizedBox(width: CruSpace.s8),
              _num('Reps', _reps),
              const SizedBox(width: CruSpace.s8),
              _num('Hold (s)', _hold),
              const SizedBox(width: CruSpace.s8),
              _num('Per day', _perDay),
            ],
          ),
          const SizedBox(height: CruSpace.s24),
          CruButton(
            label: 'Save exercise',
            expand: true,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
