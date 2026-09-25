import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dental/data/models/dental_procedure_catalog_model.dart';
import 'package:doctor_management_app/features/dental/data/seed/dental_catalog_seed.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Categories in the order dentists think of them.
const kProcedureCategories = [
  'general',
  'diagnostics',
  'preventive',
  'restorative',
  'endodontics',
  'periodontics',
  'surgery',
  'prosthodontics',
  'implantology',
  'orthodontics',
  'pediatric',
  'cosmetic',
];

String categoryLabel(String c) => switch (c.toLowerCase()) {
      'general' => 'General',
      'diagnostics' => 'Diagnostics',
      'preventive' => 'Preventive',
      'restorative' => 'Restorative',
      'endodontics' => 'Endodontics',
      'periodontics' => 'Gums (periodontics)',
      'surgery' => 'Surgery',
      'prosthodontics' => 'Crowns and dentures',
      'implantology' => 'Implants',
      'orthodontics' => 'Orthodontics',
      'pediatric' => 'Children',
      'cosmetic' => 'Cosmetic',
      final other => other.isEmpty ? 'Other' : '${other[0].toUpperCase()}${other.substring(1)}',
    };

/// The clinic's procedure list and fees: what can be picked when logging
/// a procedure or planning treatment.
class ProceduresScreen extends ConsumerStatefulWidget {
  const ProceduresScreen({super.key});

  @override
  ConsumerState<ProceduresScreen> createState() => _ProceduresScreenState();
}

class _ProceduresScreenState extends ConsumerState<ProceduresScreen> {
  String? _category;
  bool _archived = false;
  final _search = TextEditingController();
  String _query = '';
  bool _seeding = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addCommon() async {
    setState(() => _seeding = true);
    await DentalCatalogSeed.seedIfNeeded(
      ref.read(dentalRepositoryProvider),
      ref.read(dentalDoctorIdProvider),
    );
    ref.invalidate(dentalProcedureListProvider);
    if (mounted) setState(() => _seeding = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final list = ref.watch(dentalProcedureListProvider).value;
    final active = list?.where((p) => p.isActive && !p.isDeleted).toList() ?? const [];
    final archived = list?.where((p) => !p.isActive && !p.isDeleted).toList() ?? const [];
    final pool = _archived ? archived : active;
    final counts = <String, int>{};
    for (final p in active) {
      counts[p.category.toLowerCase()] = (counts[p.category.toLowerCase()] ?? 0) + 1;
    }
    final q = _query.trim().toLowerCase();
    final shown = pool
        .where((p) => _archived || _category == null || p.category.toLowerCase() == _category)
        .where((p) =>
            q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.code.toLowerCase().contains(q))
        .toList();
    final groups = <String, List<DentalProcedureCatalogModel>>{};
    for (final p in shown) {
      (groups[p.category.toLowerCase()] ??= []).add(p);
    }
    final orderedKeys = groups.keys.toList()
      ..sort((a, b) {
        final ia = kProcedureCategories.indexOf(a);
        final ib = kProcedureCategories.indexOf(b);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });

    return Padding(
      padding: CruSpace.mainPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: 'Procedures',
            subtitle: list == null
                ? ''
                : active.isEmpty
                    ? 'Your procedure list and fees'
                    : '${DashFormat.plural(active.length, 'procedure')} · '
                        '${DashFormat.plural(counts.length, 'category', 'categories')}',
            actions: [
              CruButton(
                label: 'Add procedure',
                icon: CruIcons.plus,
                onPressed: () => showProcedureCatalogDialog(context),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: CruSpace.s8,
                  runSpacing: CruSpace.s8,
                  children: [
                    DentalChoiceChip(
                      label: 'All · ${active.length}',
                      tabular: true,
                      selected: _category == null && !_archived,
                      onTap: () => setState(() {
                        _category = null;
                        _archived = false;
                      }),
                    ),
                    for (final k in kProcedureCategories.where(counts.containsKey))
                      DentalChoiceChip(
                        label: '${categoryLabel(k)} · ${counts[k]}',
                        tabular: true,
                        selected: _category == k && !_archived,
                        onTap: () => setState(() {
                          _category = k;
                          _archived = false;
                        }),
                      ),
                    for (final k in counts.keys.where((k) => !kProcedureCategories.contains(k)))
                      DentalChoiceChip(
                        label: '${categoryLabel(k)} · ${counts[k]}',
                        tabular: true,
                        selected: _category == k && !_archived,
                        onTap: () => setState(() {
                          _category = k;
                          _archived = false;
                        }),
                      ),
                    if (archived.isNotEmpty)
                      DentalChoiceChip(
                        label: 'Archived · ${archived.length}',
                        tabular: true,
                        selected: _archived,
                        onTap: () => setState(() => _archived = !_archived),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s16),
              SizedBox(
                width: 260,
                child: DentalSearchField(
                  controller: _search,
                  hint: 'Search name or code',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.cardGap),
          Expanded(
            child: CruCard(
              semanticLabel: 'Procedures',
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: list == null
                  ? const SizedBox.shrink()
                  : shown.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            child: DentalEmptyState(
                              icon: DentalIcons.procedures,
                              title: active.isEmpty && archived.isEmpty
                                  ? 'No procedures yet'
                                  : 'Nothing here',
                              body: active.isEmpty && archived.isEmpty
                                  ? 'List what you do and what you charge. Start '
                                      'with the common ones (consultation, scaling, '
                                      'fillings, root canal, crowns, extractions) '
                                      'and change the fees to yours.'
                                  : 'Try another category or search.',
                              actions: [
                                if (active.isEmpty && archived.isEmpty) ...[
                                  CruButton(
                                    label: _seeding ? 'Adding…' : 'Add common procedures',
                                    onPressed: _seeding ? null : _addCommon,
                                  ),
                                  CruButton(
                                    label: 'Add my own',
                                    kind: CruButtonKind.secondary,
                                    onPressed: () => showProcedureCatalogDialog(context),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final k in orderedKeys) ...[
                              DentalGroupLabel(categoryLabel(k),
                                  trailing: DashFormat.plural(groups[k]!.length, 'procedure')),
                              for (var i = 0; i < groups[k]!.length; i++) ...[
                                if (i > 0) const CruSeparator(indent: 12),
                                _ProcedureRow(item: groups[k]![i]),
                              ],
                            ],
                          ],
                        ),
            ),
          ),
          if (list != null && active.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s10),
            Text(
              'These fees fill in when you plan treatment. You can still change '
              'the amount for each patient.',
              style: CruType.caption.tint(c.label3),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcedureRow extends ConsumerWidget {
  const _ProcedureRow({required this.item});

  final DentalProcedureCatalogModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final archived = !item.isActive;
    return DentalListRow(
      semanticLabel: item.name,
      onTap: () => showProcedureCatalogDialog(context, existing: item),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CruInfoPill(text: item.code, tabular: true),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CruType.callout.tint(archived ? c.label3 : c.label),
            ),
          ),
          if (item.requiresToothSelection) ...[
            CruPill(text: 'Per tooth', background: c.inset, foreground: c.label2),
            const SizedBox(width: CruSpace.s12),
          ],
          SizedBox(
            width: 70,
            child: Text(
              item.defaultDurationMinutes == null
                  ? ''
                  : DashFormat.minutes(item.defaultDurationMinutes!),
              textAlign: TextAlign.right,
              style: CruType.subhead.tabular.tint(c.label2),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              item.defaultPrice == null ? '—' : DashFormat.rupees(item.defaultPrice!),
              textAlign: TextAlign.right,
              style: CruType.row.tabular.tint(archived ? c.label3 : c.label),
            ),
          ),
          if (archived) ...[
            const SizedBox(width: CruSpace.s12),
            CruCapsuleButton(
              label: 'Restore',
              onPressed: () async {
                await ref.read(dentalRepositoryProvider).restoreCatalogItem(item.id);
                ref.invalidate(dentalProcedureListProvider);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ================================================================ dialog

Future<bool> showProcedureCatalogDialog(
  BuildContext context, {
  DentalProcedureCatalogModel? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CatalogDialog(existing: existing),
  );
  return saved == true;
}

class _CatalogDialog extends ConsumerStatefulWidget {
  const _CatalogDialog({required this.existing});

  final DentalProcedureCatalogModel? existing;

  @override
  ConsumerState<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends ConsumerState<_CatalogDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _price;
  late final TextEditingController _minutes;
  late String _category;
  late bool _perTooth;
  bool _codeTouched = false;
  bool _saving = false;
  bool _dirty = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _price = TextEditingController(
        text: e?.defaultPrice == null ? '' : e!.defaultPrice!.round().toString());
    _minutes = TextEditingController(
        text: e?.defaultDurationMinutes?.toString() ?? '');
    _category = (e?.category ?? 'general').toLowerCase();
    _perTooth = e?.requiresToothSelection ?? true;
    _codeTouched = e != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _price.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _edited() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// "Root canal treatment" → "RCT"-style initials, until the code is typed.
  void _suggestCode() {
    if (_codeTouched) return;
    final words = _name.text
        .trim()
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    _code.text = words.length == 1
        ? words.first.toUpperCase().substring(0, words.first.length.clamp(0, 5))
        : words.map((w) => w[0].toUpperCase()).join();
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final now = DateTime.now();
      final e = widget.existing;
      await ref.read(dentalRepositoryProvider).saveCatalogItem(
            DentalProcedureCatalogModel(
              id: e?.id ?? const Uuid().v4(),
              doctorId: ref.read(dentalDoctorIdProvider),
              code: _code.text.trim().toUpperCase(),
              name: _name.text.trim(),
              category: _category,
              defaultPrice: double.tryParse(_price.text.trim()),
              defaultDurationMinutes: int.tryParse(_minutes.text.trim()),
              requiresToothSelection: _perTooth,
              isActive: e?.isActive ?? true,
              createdAt: e?.createdAt ?? now,
              updatedAt: now,
              syncStatus: 'pending',
            ),
          );
      ref.invalidate(dentalProcedureListProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() {
        _saving = false;
        _notice = "Couldn't save the procedure. Try again.";
      });
    }
  }

  Future<void> _archive() async {
    final e = widget.existing;
    if (e == null) return;
    await ref.read(dentalRepositoryProvider).archiveCatalogItem(e.id);
    ref.invalidate(dentalProcedureListProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return CruFormDialog(
      title: e == null ? 'Add procedure' : e.name,
      subtitle: e == null ? 'To your procedure list' : categoryLabel(e.category),
      leading: const CruIconTile(icon: DentalIcons.procedures, tone: CruTileTone.accent),
      submitLabel: e == null ? 'Add procedure' : 'Save changes',
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      footerHint: 'Ctrl + Enter to save',
      body: Form(
        key: _form,
        autovalidateMode:
            _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              title: 'Procedure',
              children: [
                CruFieldRow(
                  flex: const [3, 1],
                  children: [
                    CruTextField(
                      label: 'Name',
                      controller: _name,
                      autofocus: e == null,
                      hint: 'Root canal treatment (molar)',
                      textCapitalization: TextCapitalization.sentences,
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Name the procedure.' : null,
                      onChanged: (_) {
                        setState(_suggestCode);
                        _edited();
                      },
                    ),
                    CruTextField(
                      label: 'Code',
                      controller: _code,
                      hint: 'RCT',
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Add a short code.' : null,
                      onChanged: (_) {
                        _codeTouched = true;
                        _edited();
                      },
                    ),
                  ],
                ),
                CruFieldFrame(
                  label: 'Category',
                  child: DentalChipWrap<String>(
                    options: kProcedureCategories,
                    label: categoryLabel,
                    isSelected: (k) => k == _category,
                    onTap: (k) {
                      setState(() => _category = k);
                      _edited();
                    },
                  ),
                ),
              ],
            ),
            CruFormSection(
              title: 'Fee and time',
              description: 'Filled in when you plan treatment; change it per patient.',
              children: [
                CruFieldRow(
                  children: [
                    CruTextField(
                      label: 'Fee',
                      optional: true,
                      controller: _price,
                      prefix: '₹',
                      hint: '0',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _edited(),
                    ),
                    CruTextField(
                      label: 'Chair time (min)',
                      optional: true,
                      controller: _minutes,
                      hint: '30',
                      tabular: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => _edited(),
                    ),
                  ],
                ),
                CruFieldFrame(
                  label: 'Charged',
                  help: _perTooth
                      ? 'The fee is multiplied by the number of teeth in a plan.'
                      : 'One fee per visit, whatever the teeth.',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CruSegmentedControl<bool>(
                      semanticLabel: 'Charged',
                      segments: const [
                        CruSegment(true, 'Per tooth'),
                        CruSegment(false, 'Per visit'),
                      ],
                      selected: _perTooth,
                      onChanged: (v) {
                        setState(() => _perTooth = v);
                        _edited();
                      },
                    ),
                  ),
                ),
                if (e != null && e.isActive)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CruLink(
                      label: 'Archive: hide it from the pickers',
                      onPressed: _archive,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
