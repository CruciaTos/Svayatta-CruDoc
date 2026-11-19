import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_totality.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Full screen: the symptoms of the case sheet, each given a tier and a
/// miasm by the physician, with the ordered totality at the top.
class HomeopathyTotalityScreen extends ConsumerStatefulWidget {
  const HomeopathyTotalityScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  ConsumerState<HomeopathyTotalityScreen> createState() =>
      _HomeopathyTotalityScreenState();
}

class _HomeopathyTotalityScreenState
    extends ConsumerState<HomeopathyTotalityScreen> {
  List<HomeoTotalityItem>? _items;
  List<String> _miasmCase = [];
  DentalRecord? _record;
  bool _dirty = false;
  int? _open;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sheet = await ref.read(
      homeopathyCaseSheetProvider(widget.patientId).future,
    );
    final recs = await ref.read(
      patientRecordsProvider((
        patientId: widget.patientId,
        kind: RecKind.homeoTotality,
      )).future,
    );
    final saved = recs.isEmpty ? null : HomeoTotality.fromRecord(recs.first);
    if (!mounted) return;
    setState(() {
      _record = recs.firstOrNull;
      _miasmCase = [...?saved?.miasmCase];
      _items = mergeTotality(
        sheet == null ? const [] : symptomsFromCaseSheet(sheet),
        saved?.items ?? const [],
      );
      // The text may have changed since the last save, so keep it in step.
      if (saved != null) _dirty = true;
    });
  }

  Future<void> _save() async {
    final items = _items;
    if (items == null) return;
    final data = HomeoTotality(items: items, miasmCase: _miasmCase).toData()
      ..['patientId'] = widget.patientId;
    final rec =
        _record?.copyWith(data: data) ??
        DentalRecord.create(widget.patientId, RecKind.homeoTotality, data);
    await saveDentalRecord(ref, rec);
    _record = rec;
    _dirty = false;
  }

  void _update(int i, HomeoTotalityItem item) => setState(() {
    _items = [..._items!]..[i] = item;
    _dirty = true;
  });

  Future<void> _copy() async {
    final text = totalityText(_items ?? const []);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) recToast(context, 'Totality copied.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final items = _items;
    final totality = [
      for (final t in const [HomeoTier.mentalGeneral, HomeoTier.characteristic])
        for (final i in items ?? const <HomeoTotalityItem>[])
          if (!i.skip && i.tier == t) i,
    ];
    final dom = items == null ? null : dominantMiasm(items, _miasmCase);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && _dirty) await _save();
      },
      child: Scaffold(
        backgroundColor: c.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s12,
                  vertical: CruSpace.s8,
                ),
                child: Row(
                  children: [
                    CruIconButton(
                      icon: CruIcons.chevronLeft,
                      onPressed: () => Navigator.pop(context),
                      semanticLabel: 'Back',
                    ),
                    const SizedBox(width: CruSpace.s4),
                    Expanded(
                      child: Text(
                        'Totality',
                        style: CruType.title2.tint(c.label),
                      ),
                    ),
                    CruCapsuleButton(
                      label: 'Copy totality',
                      onPressed: totality.isEmpty ? null : _copy,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items == null
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: CruSpace.mainPaddingPhone,
                        children: [
                          _SummaryCard(totality: totality, dominant: dom),
                          const SizedBox(height: CruSpace.cardGap),
                          _MiasmCaseCard(
                            selected: _miasmCase,
                            dominant: dom,
                            onToggle: (m) => setState(() {
                              _miasmCase = _miasmCase.contains(m)
                                  ? (_miasmCase.where((x) => x != m).toList())
                                  : [..._miasmCase, m];
                              _dirty = true;
                            }),
                          ),
                          const SizedBox(height: CruSpace.cardGap),
                          if (items.isEmpty)
                            CruCard(
                              padding: const EdgeInsets.all(CruSpace.s16),
                              child: Text(
                                'The case sheet has no symptoms to list yet.',
                                style: CruType.text.tint(c.label2),
                              ),
                            )
                          else
                            CruCard(
                              padding: const EdgeInsets.all(CruSpace.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Symptoms',
                                    style: CruType.headline.tint(c.label),
                                  ),
                                  const SizedBox(height: CruSpace.s4),
                                  Text(
                                    'Tap a symptom to set its tier and miasm.',
                                    style: CruType.caption.tint(c.label2),
                                  ),
                                  const SizedBox(height: CruSpace.s8),
                                  for (var i = 0; i < items.length; i++)
                                    _SymptomRow(
                                      item: items[i],
                                      open: _open == i,
                                      last: i == items.length - 1,
                                      onTap: () => setState(
                                        () => _open = _open == i ? null : i,
                                      ),
                                      onChanged: (n) => _update(i, n),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: CruSpace.s16),
                          CruButton(
                            label: 'Save',
                            expand: true,
                            onPressed: () async {
                              await _save();
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totality, required this.dominant});

  final List<HomeoTotalityItem> totality;
  final ({String name, int count, int of})? dominant;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Totality', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s6),
          if (totality.isEmpty)
            Text(
              'Mark symptoms as characteristic or mental general to build '
              'the totality.',
              style: CruType.text.tint(c.label2),
            )
          else
            for (var i = 0; i < totality.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: CruSpace.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: CruSpace.s24,
                      child: Text(
                        '${i + 1}.',
                        style: CruType.text.tabular.tint(c.label3),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        totality[i].text,
                        style: CruType.text.tint(c.label),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s8),
                    Text(
                      totality[i].tier!.label,
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
              ),
          if (dominant != null) ...[
            const SizedBox(height: CruSpace.s12),
            Text(
              dominantLine(dominant!),
              style: CruType.caption.tabular.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiasmCaseCard extends StatelessWidget {
  const _MiasmCaseCard({
    required this.selected,
    required this.dominant,
    required this.onToggle,
  });

  final List<String> selected;
  final ({String name, int count, int of})? dominant;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Miasm of the case', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(
            'For the whole case; symptoms can carry their own.',
            style: CruType.caption.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s12),
          Wrap(
            spacing: CruSpace.s6,
            runSpacing: CruSpace.s6,
            children: [
              for (final m in homeoMiasms)
                HomeopathyChoiceChip(
                  label: _cap(m),
                  selected: selected.contains(m),
                  onSelected: (_) => onToggle(m),
                ),
            ],
          ),
          if (dominant != null) ...[
            const SizedBox(height: CruSpace.s12),
            Text(
              dominantLine(dominant!),
              style: CruType.callout.w600.tabular.tint(c.label),
            ),
          ],
        ],
      ),
    );
  }
}

class _SymptomRow extends StatelessWidget {
  const _SymptomRow({
    required this.item,
    required this.open,
    required this.last,
    required this.onTap,
    required this.onChanged,
  });

  final HomeoTotalityItem item;
  final bool open;
  final bool last;
  final VoidCallback onTap;
  final ValueChanged<HomeoTotalityItem> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final marks = [
      item.source,
      if (item.skip) 'left out',
      if (item.tier != null) item.tier!.label,
      if (item.miasm.isNotEmpty) item.miasm,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruPressable(
          onTap: onTap,
          semanticLabel: item.text,
          builder: (context, hovered) => Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  style: CruType.text.tint(item.skip ? c.label3 : c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(marks, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
        ),
        if (open) ...[
          Wrap(
            spacing: CruSpace.s6,
            runSpacing: CruSpace.s6,
            children: [
              for (final t in HomeoTier.values)
                HomeopathyChoiceChip(
                  label: t.label,
                  selected: item.tier == t,
                  onSelected: (sel) => onChanged(
                    sel
                        ? item.copyWith(tier: t)
                        : item.copyWith(clearTier: true),
                  ),
                ),
              HomeopathyChoiceChip(
                label: 'Leave out',
                selected: item.skip,
                onSelected: (sel) => onChanged(item.copyWith(skip: sel)),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          Wrap(
            spacing: CruSpace.s6,
            runSpacing: CruSpace.s6,
            children: [
              for (final m in homeoMiasms)
                HomeopathyChoiceChip(
                  label: _cap(m),
                  selected: item.miasm == m,
                  onSelected: (sel) =>
                      onChanged(item.copyWith(miasm: sel ? m : '')),
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
        ],
        if (!last) Container(height: 1, color: c.separator),
      ],
    );
  }
}
