import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/homeopathy/data/homeopathy_dispensing.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/homeopathy_remedy_stock_screen.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_potency_chips.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_remedy_field.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_remedy_inputs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What was dispensed to this patient, newest first. "Dispense" logs a new
/// one (and takes it off the clinic's remedy stock when that is tracked);
/// "Remedy stock" opens the clinic-wide stock list.
class HomeopathyDispensedCard extends ConsumerWidget {
  const HomeopathyDispensedCard({super.key, required this.patientId});

  final String patientId;

  Future<void> _dispense(BuildContext context, WidgetRef ref) {
    final sheet = ref.read(homeopathyCaseSheetProvider(patientId)).value;
    return showHomeoSheet<void>(
      context,
      (_) => _DispenseSheet(
        patientId: patientId,
        initialRemedy: sheet?.prescriptionNotes.prescribedRemedy ?? '',
        initialPotency: sheet?.prescriptionNotes.potency ?? '',
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RemedyDispense d,
  ) async {
    final restores = d.stockId.isNotEmpty && d.stockTaken > 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Delete this entry?',
        leading: const CruIconTile(
          icon: CruIcons.warning,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Delete',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            restores
                ? 'The ${DateFormat('d MMM yyyy').format(d.date)} entry is '
                      'removed and ${d.stockTaken} ${d.unit} go back into '
                      'stock.'
                : 'The ${DateFormat('d MMM yyyy').format(d.date)} entry is '
                      'removed.',
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
      ),
    );
    if (confirm == true) await deleteDispense(ref, d);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final items =
        ref.watch(homeoDispensesProvider(patientId)).value ??
        const <RemedyDispense>[];

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Dispensed', style: CruType.headline.tint(c.label)),
              ),
              CruPressable(
                onTap: () => _dispense(context, ref),
                semanticLabel: 'Dispense',
                builder: (context, hovered) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruIcon(CruIcons.plus, size: CruSpace.s16, color: c.accent),
                    const SizedBox(width: CruSpace.s4),
                    Text(
                      'Dispense',
                      style: CruType.subhead.w600.tint(c.accentText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          if (items.isEmpty)
            Text('Nothing dispensed yet.', style: CruType.text.tint(c.label2))
          else
            for (var i = 0; i < items.length; i++)
              _DispenseRow(
                item: items[i],
                last: i == items.length - 1,
                onDelete: () => _delete(context, ref, items[i]),
              ),
          const SizedBox(height: CruSpace.s12),
          CruLink(
            label: 'Remedy stock',
            onPressed: () => HomeopathyRemedyStockScreen.open(context),
          ),
        ],
      ),
    );
  }
}

class _DispenseRow extends StatelessWidget {
  const _DispenseRow({
    required this.item,
    required this.last,
    required this.onDelete,
  });

  final RemedyDispense item;
  final bool last;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final detail = ['${item.qty} ${item.unit}', item.form.label].join(' · ');
    return Padding(
      padding: EdgeInsets.only(
        top: CruSpace.s8,
        bottom: last ? 0 : CruSpace.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('d MMM yyyy').format(item.date),
                  style: CruType.caption.tabular.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  remedyLabel(item.remedy, item.potency),
                  style: CruType.callout.w600.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(detail, style: CruType.caption.tabular.tint(c.label2)),
                if (item.note.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(item.note, style: CruType.caption.tint(c.label2)),
                ],
              ],
            ),
          ),
          CruIconButton(
            icon: FileIcons.trash,
            iconSize: 16,
            onPressed: onDelete,
            semanticLabel: 'Delete dispense entry',
          ),
        ],
      ),
    );
  }
}

class _DispenseSheet extends ConsumerStatefulWidget {
  const _DispenseSheet({
    required this.patientId,
    required this.initialRemedy,
    required this.initialPotency,
  });

  final String patientId;
  final String initialRemedy;
  final String initialPotency;

  @override
  ConsumerState<_DispenseSheet> createState() => _DispenseSheetState();
}

class _DispenseSheetState extends ConsumerState<_DispenseSheet> {
  late final _remedy = TextEditingController(text: widget.initialRemedy);
  late final _potency = TextEditingController(text: widget.initialPotency);
  final _note = TextEditingController();
  RemedyForm _form = RemedyForm.pills;
  int _qty = 1;
  bool _saving = false;

  @override
  void dispose() {
    _remedy.dispose();
    _potency.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _remedy.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await dispenseRemedy(
      ref,
      patientId: widget.patientId,
      remedy: _remedy.text,
      potency: _potency.text,
      form: _form,
      qty: _qty,
      note: _note.text,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final stock = ref.watch(homeoStockProvider).value ?? const [];
    return HomeoSheetBody(
      title: 'Dispense remedy',
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
          label: 'Quantity',
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
            final short = _qty > line.qty;
            return Padding(
              padding: const EdgeInsets.only(top: CruSpace.s8),
              child: Text(
                short
                    ? 'Only ${line.qty} ${line.unit} in stock; stock goes to 0.'
                    : 'In stock: ${line.qty} ${line.unit}',
                style: CruType.caption.tabular.tint(
                  short ? c.amberText : c.label2,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: CruSpace.s12),
        HomeopathyFormField(
          controller: _note,
          label: 'Note',
          hint: 'Dose instructions, batch, anything to remember',
          maxLines: 3,
        ),
        const SizedBox(height: CruSpace.s16),
        ListenableBuilder(
          listenable: _remedy,
          builder: (context, _) => CruButton(
            label: 'Save',
            expand: true,
            onPressed: _remedy.text.trim().isEmpty || _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
