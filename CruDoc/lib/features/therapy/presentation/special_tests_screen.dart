import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/data/special_tests.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens the detail page of one special test for [patient].
void openSpecialTest(BuildContext context, Patient patient, SpecialTest t) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => SpecialTestDetailScreen(patient: patient, test: t),
      ),
    );

/// Special tests library: search, region chips, tap for the detail page.
class SpecialTestsScreen extends ConsumerStatefulWidget {
  const SpecialTestsScreen({super.key, required this.patient});

  final Patient patient;

  @override
  ConsumerState<SpecialTestsScreen> createState() => _SpecialTestsScreenState();
}

class _SpecialTestsScreenState extends ConsumerState<SpecialTestsScreen> {
  final _search = TextEditingController();
  TestRegion? _region;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final q = _search.text.trim().toLowerCase();
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: widget.patient.id,
        kind: RecKind.physioTestResult,
      )),
    );
    final done = <String>{
      for (final r in testResults(recs.value ?? const <DentalRecord>[]))
        r.testId,
    };
    final shown = [
      for (final t in kSpecialTests)
        if ((_region == null || t.region == _region) &&
            (q.isEmpty ||
                t.name.toLowerCase().contains(q) ||
                t.assesses.toLowerCase().contains(q)))
          t,
    ];

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Special tests')),
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
              hint: 'Test or what it assesses',
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
                for (final r in TestRegion.values) ...[
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
                      'No tests match.',
                      style: CruType.caption.tint(c.label3),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(CruSpace.s16),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: CruSpace.s8),
                    itemBuilder: (_, i) {
                      final t = shown[i];
                      return CruCard(
                        child: InkWell(
                          onTap: () =>
                              openSpecialTest(context, widget.patient, t),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.name,
                                      style: CruType.body.w600.tint(c.label),
                                    ),
                                    const SizedBox(height: CruSpace.s2),
                                    Text(
                                      t.region.label,
                                      style: CruType.caption.tint(c.label2),
                                    ),
                                  ],
                                ),
                              ),
                              if (done.contains(t.id))
                                CruIcon(CruIcons.check, color: c.label2),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One test: what it checks, steps, what counts as positive, and this
/// patient's earlier results.
class SpecialTestDetailScreen extends ConsumerWidget {
  const SpecialTestDetailScreen({
    super.key,
    required this.patient,
    required this.test,
  });

  final Patient patient;
  final SpecialTest test;

  Future<void> _record(BuildContext context, WidgetRef ref) async {
    final data = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResultSheet(testId: test.id),
    );
    if (data == null) return;
    await saveDentalRecord(
      ref,
      DentalRecord.create(patient.id, RecKind.physioTestResult, data),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TestResult r,
  ) async {
    final ok = await confirmDental(
      context,
      title: 'Delete this result?',
      body:
          '${test.name}, ${TestResult.resultLabel(r.result).toLowerCase()} on ${DentalFormat.date(r.date)}, will be removed.',
      action: 'Delete',
    );
    if (ok) await deleteDentalRecord(ref, r.record);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioTestResult,
      )),
    );
    final history = testResults(
      recs.value ?? const <DentalRecord>[],
    ).where((r) => r.testId == test.id).toList();

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(
        top: CruSpace.s16,
        bottom: CruSpace.s8,
      ),
      child: Text(text, style: CruType.micro.w600.tint(c.label2)),
    );

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: Text(test.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(CruSpace.s16),
              children: [
                Text(
                  test.region.label,
                  style: CruType.caption.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s4),
                Text(test.assesses, style: CruType.body.tint(c.label)),
                heading('HOW TO DO IT'),
                for (var i = 0; i < test.steps.length; i++) ...[
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
                            style: CruType.caption.w600.tabular.tint(c.label),
                          ),
                        ),
                        const SizedBox(width: CruSpace.s12),
                        Expanded(
                          child: Text(
                            test.steps[i],
                            style: CruType.body.tint(c.label),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CruSpace.s8),
                ],
                heading('POSITIVE WHEN'),
                Text(test.positive, style: CruType.body.tint(c.label)),
                heading('WHAT IT MAY SUGGEST'),
                Text(test.suggests, style: CruType.body.tint(c.label)),
                heading('THIS PATIENT'),
                if (history.isEmpty)
                  Text(
                    'No result recorded yet.',
                    style: CruType.caption.tint(c.label3),
                  ),
                for (final r in history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CruSpace.s8),
                    child: CruCard(
                      padding: const EdgeInsets.fromLTRB(
                        CruSpace.s16,
                        CruSpace.s12,
                        CruSpace.s4,
                        CruSpace.s12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DentalFormat.date(r.date),
                                  style: CruType.caption.tabular.tint(
                                    c.label2,
                                  ),
                                ),
                                const SizedBox(height: CruSpace.s2),
                                Text(
                                  '${TestResult.resultLabel(r.result)} · ${TestResult.sideLabel(r.side)}',
                                  style: CruType.body.w600.tint(c.label),
                                ),
                                if (r.note.isNotEmpty)
                                  Text(
                                    r.note,
                                    style: CruType.caption.tint(c.label2),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: c.label2,
                            ),
                            onPressed: () => _delete(context, ref, r),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: CruButton(
                label: 'Record result',
                expand: true,
                onPressed: () => _record(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSheet extends StatefulWidget {
  const _ResultSheet({required this.testId});

  final String testId;

  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  String _result = 'negative';
  String _side = 'both';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    Widget group(
      String title,
      List<String> values,
      String current,
      String Function(String) label,
      ValueChanged<String> onTap,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: CruType.body.w600.tint(c.label)),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s8,
            runSpacing: CruSpace.s8,
            children: [
              for (final v in values)
                DentalChoiceChip(
                  label: label(v),
                  selected: v == current,
                  onTap: () => onTap(v),
                ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CruSpace.s16,
            0,
            CruSpace.s16,
            CruSpace.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              group(
                'Result',
                const ['positive', 'negative', 'notDone'],
                _result,
                TestResult.resultLabel,
                (v) => setState(() => _result = v),
              ),
              group(
                'Side',
                const ['left', 'right', 'both'],
                _side,
                TestResult.sideLabel,
                (v) => setState(() => _side = v),
              ),
              CruTextField(
                label: 'Note',
                controller: _note,
                optional: true,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: CruSpace.s16),
              CruButton(
                label: 'Save result',
                expand: true,
                onPressed: () => Navigator.of(context).pop(
                  TestResult.toData(
                    testId: widget.testId,
                    side: _side,
                    result: _result,
                    note: _note.text.trim(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
