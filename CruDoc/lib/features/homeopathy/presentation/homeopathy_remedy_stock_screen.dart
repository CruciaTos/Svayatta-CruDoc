import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/homeopathy/data/homeopathy_dispensing.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_potency_chips.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_remedy_field.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_remedy_inputs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Widest the list grows on desktop.
const double _maxWidth = 760;

/// The clinic's remedy stock: remedy + potency + form with the quantity on
/// hand. Dispensing from a patient's case sheet takes from these lines.
class HomeopathyRemedyStockScreen extends ConsumerStatefulWidget {
  const HomeopathyRemedyStockScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const HomeopathyRemedyStockScreen(),
    ),
  );

  @override
  ConsumerState<HomeopathyRemedyStockScreen> createState() =>
      _HomeopathyRemedyStockScreenState();
}

class _HomeopathyRemedyStockScreenState
    extends ConsumerState<HomeopathyRemedyStockScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final all = ref.watch(homeoStockProvider).value ?? const [];

    Widget centred(Widget child) => Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: child,
      ),
    );

    OutlineInputBorder ring(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CruRadius.control),
      borderSide: BorderSide(color: color, width: 1.5),
    );

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            centred(
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
                        'Remedy stock',
                        style: CruType.title2.tint(c.label),
                      ),
                    ),
                    CruButton(
                      label: 'Add stock',
                      icon: CruIcons.plus,
                      onPressed: () => showHomeoSheet<void>(
                        context,
                        (_) => const _AddStockSheet(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s20,
                  CruSpace.s8,
                  CruSpace.s20,
                  CruSpace.s32,
                ),
                physics: const ClampingScrollPhysics(),
                children: [
                  centred(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (all.isNotEmpty) ...[
                          TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: CruType.input.tint(c.label),
                            cursorColor: c.accent,
                            decoration: InputDecoration(
                              hintText: 'Search remedies',
                              hintStyle: CruType.input.tint(c.label3),
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(CruSpace.s12),
                                child: CruIcon(
                                  CruIcons.search,
                                  size: CruSpace.s16,
                                  color: c.label3,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: CruSpace.s12,
                                vertical: CruSpace.s12,
                              ),
                              filled: true,
                              fillColor: c.inset,
                              border: ring(c.inset.withValues(alpha: 0)),
                              enabledBorder: ring(c.inset.withValues(alpha: 0)),
                              focusedBorder: ring(c.accent),
                            ),
                          ),
                          const SizedBox(height: CruSpace.cardGap),
                        ],
                        _list(context, all),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<RemedyStockLine> all) {
    final c = context.cru;
    if (all.isEmpty) {
      return CruCard(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: Text(
          'No remedy stock yet. Add stock to track what you have on hand.',
          style: CruType.text.tint(c.label2),
        ),
      );
    }
    final q = _search.text.trim().toLowerCase();
    final rows = [
      for (final s in all)
        if (q.isEmpty ||
            '${s.remedy} ${s.potency} ${s.form.label}'.toLowerCase().contains(
              q,
            ))
          s,
    ];
    if (rows.isEmpty) {
      return CruCard(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: Text('No match.', style: CruType.text.tint(c.label2)),
      );
    }
    return CruCard(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.separator),
            _StockRow(
              line: rows[i],
              onTap: () => showHomeoSheet<void>(
                context,
                (_) => _EditStockSheet(line: rows[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.line, required this.onTap});

  final RemedyStockLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Edit ${remedyLabel(line.remedy, line.potency)}',
      builder: (context, hovered) => Container(
        color: hovered ? c.hoverFill : null,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s16,
          vertical: CruSpace.s12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    remedyLabel(line.remedy, line.potency),
                    style: CruType.callout.w600.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(line.form.label, style: CruType.caption.tint(c.label2)),
                ],
              ),
            ),
            if (line.isLow) ...[
              CruPill(
                text: 'Low',
                background: c.amberTint,
                foreground: c.amberText,
              ),
              const SizedBox(width: CruSpace.s10),
            ],
            Text(
              '${line.qty} ${line.unit}',
              style: CruType.callout.w600.tabular.tint(c.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddStockSheet extends ConsumerStatefulWidget {
  const _AddStockSheet();

  @override
  ConsumerState<_AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends ConsumerState<_AddStockSheet> {
  final _remedy = TextEditingController();
  final _potency = TextEditingController();
  RemedyForm _form = RemedyForm.pills;
  int _qty = 1;
  bool _saving = false;

  @override
  void dispose() {
    _remedy.dispose();
    _potency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _remedy.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await addRemedyStock(
      ref,
      remedy: _remedy.text,
      potency: _potency.text,
      form: _form,
      qty: _qty,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final stock = ref.watch(homeoStockProvider).value ?? const [];
    return HomeoSheetBody(
      title: 'Add stock',
      children: [
        HomeopathyRemedyField(
          controller: _remedy,
          label: 'Remedy',
          hint: 'Search or type a remedy',
        ),
        const SizedBox(height: CruSpace.s12),
        HomeopathyPotencyChips(controller: _potency),
        const SizedBox(height: CruSpace.s12),
        RemedyFormChips(
          selected: _form,
          onChanged: (f) => setState(() => _form = f),
        ),
        const SizedBox(height: CruSpace.s12),
        RemedyQtyStepper(
          label: 'Quantity to add',
          value: _qty,
          unit: _form.unit,
          onChanged: (v) => setState(() => _qty = v),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_remedy, _potency]),
          builder: (context, _) {
            final line = stock
                .where((s) => s.matches(_remedy.text, _potency.text, _form))
                .firstOrNull;
            if (line == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: CruSpace.s8),
              child: Text(
                'Adds to the ${line.qty} ${line.unit} already on hand.',
                style: CruType.caption.tabular.tint(c.label2),
              ),
            );
          },
        ),
        const SizedBox(height: CruSpace.s16),
        ListenableBuilder(
          listenable: _remedy,
          builder: (context, _) => CruButton(
            label: 'Add',
            expand: true,
            onPressed: _remedy.text.trim().isEmpty || _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

class _EditStockSheet extends ConsumerStatefulWidget {
  const _EditStockSheet({required this.line});

  final RemedyStockLine line;

  @override
  ConsumerState<_EditStockSheet> createState() => _EditStockSheetState();
}

class _EditStockSheetState extends ConsumerState<_EditStockSheet> {
  late int _qty = widget.line.qty;

  /// 0 means no low-stock level.
  late int _low = widget.line.lowLevel ?? 0;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await updateRemedyStock(
      ref,
      widget.line,
      qty: _qty,
      low: _low > 0 ? _low : null,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Remove this stock line?',
        leading: const CruIconTile(
          icon: CruIcons.warning,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Remove',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            '${remedyLabel(widget.line.remedy, widget.line.potency)} '
            '(${widget.line.form.label}) is no longer tracked. Past '
            'dispenses stay in each patient\'s record.',
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    await deleteRemedyStock(ref, widget.line);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final line = widget.line;
    return HomeoSheetBody(
      title: remedyLabel(line.remedy, line.potency),
      children: [
        Text(line.form.label, style: CruType.caption.tint(c.label2)),
        const SizedBox(height: CruSpace.s16),
        RemedyQtyStepper(
          label: 'On hand',
          value: _qty,
          unit: line.unit,
          min: 0,
          onChanged: (v) => setState(() => _qty = v),
        ),
        const SizedBox(height: CruSpace.s16),
        RemedyQtyStepper(
          label: 'Low-stock level',
          value: _low,
          unit: _low == 0 ? 'off' : line.unit,
          min: 0,
          onChanged: (v) => setState(() => _low = v),
        ),
        const SizedBox(height: CruSpace.s16),
        CruButton(label: 'Save', expand: true, onPressed: _save),
        const SizedBox(height: CruSpace.s8),
        CruButton(
          label: 'Remove stock line',
          kind: CruButtonKind.inset,
          expand: true,
          onPressed: _remove,
        ),
      ],
    );
  }
}
