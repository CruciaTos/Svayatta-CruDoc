import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/revenue/data/invoice_pdf_mapper.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

export 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';

/// Which invoices the list shows.
enum _InvoiceFilter {
  all('All'),
  paid('Paid'),
  pending('Pending'),
  overdue('Overdue');

  const _InvoiceFilter(this.label);
  final String label;

  bool matches(InvoiceModel i) => switch (this) {
    _InvoiceFilter.all => true,
    _InvoiceFilter.paid => i.isPaid && !i.isCancelled,
    _InvoiceFilter.pending => i.isPending && !i.isCancelled,
    _InvoiceFilter.overdue => i.isOverdue && !i.isCancelled,
  };
}

/// Revenue › Invoices on the desktop: the totals at a glance, a status
/// filter and search, the invoices in one card and the selected one's
/// details beside it. Follows Day and Evening like the rest of Revenue.
class DesktopInvoicesScreen extends StatefulWidget {
  const DesktopInvoicesScreen({
    super.key,
    this.isSubScreen = false,
    @visibleForTesting this.invoices,
  });

  /// Hosted under Revenue's header (no page title of its own).
  final bool isSubScreen;

  /// Tests: the invoices to show instead of the clinic's.
  final Stream<List<InvoiceModel>>? invoices;

  @override
  State<DesktopInvoicesScreen> createState() => _DesktopInvoicesScreenState();
}

class _DesktopInvoicesScreenState extends State<DesktopInvoicesScreen> {
  late final InvoiceRepository _repository = InvoiceRepository();
  final PatientRepository _patientRepository = PatientRepository();
  final TextEditingController _search = TextEditingController();
  late final Stream<List<InvoiceModel>> _invoices =
      widget.invoices ?? _repository.watchInvoices();

  _InvoiceFilter _filter = _InvoiceFilter.all;
  String? _selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _newInvoice() =>
      showDesktopCreateInvoiceDialog(context, repository: _repository);

  List<InvoiceModel> _shown(List<InvoiceModel> all) {
    final q = _search.text.toLowerCase().trim();
    return [
      for (final i in all)
        if (_filter.matches(i) &&
            (q.isEmpty ||
                i.patientName.toLowerCase().contains(q) ||
                i.service.toLowerCase().contains(q) ||
                i.id.toLowerCase().contains(q) ||
                i.invoiceNumber.toLowerCase().contains(q)))
          i,
    ];
  }

  Future<void> _viewPdf(InvoiceModel invoice) async {
    Patient? patient;
    if (invoice.patientId != null && invoice.patientId!.isNotEmpty) {
      try {
        final patients = await _patientRepository.watchPatients().first;
        patient = patients.where((p) => p.id == invoice.patientId).firstOrNull;
      } catch (_) {}
    }

    if (!mounted) return;
    await MedicalPdfPreviewScreen.open(
      context,
      documentData: invoicePdfData(invoice, patient: patient),
      invoice: invoice,
    );
  }

  void _edit(InvoiceModel invoice) {
    showDesktopCreateInvoiceDialog(context, initialInvoice: invoice);
  }

  Future<void> _cancel(InvoiceModel invoice) async {
    final num = invoice.invoiceNumber.isNotEmpty
        ? invoice.invoiceNumber
        : invoice.id;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel invoice $num?'),
        content: const Text(
          'It stays in your records with its number, marked cancelled, '
          'and leaves your revenue.',
        ),
        actions: [
          CruButton(
            label: 'Keep',
            kind: CruButtonKind.inset,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CruButton(
            label: 'Cancel invoice',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await _repository.cancelInvoice(invoice.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return StreamBuilder<List<InvoiceModel>>(
      stream: _invoices,
      builder: (context, snapshot) {
        final all = snapshot.data;
        final shown = all == null ? const <InvoiceModel>[] : _shown(all);
        InvoiceModel? selected;
        for (final i in all ?? const <InvoiceModel>[]) {
          if (i.id == _selectedId) selected = i;
        }

        final Widget list;
        if (snapshot.hasError && all == null) {
          list = _MessageCard(
            icon: CruIcons.warning,
            title: "Couldn't load invoices",
            body: 'Check the connection and try again.',
          );
        } else if (all == null) {
          list = CruCard(
            child: Center(
              child: Text(
                'Loading invoices…',
                style: CruType.subhead.tint(c.label2),
              ),
            ),
          );
        } else if (shown.isEmpty) {
          list = _MessageCard(
            icon: CruIcons.fileText,
            title: all.isEmpty ? 'No invoices yet' : 'No invoices here',
            body: all.isEmpty
                ? 'Invoices you create, or bills from visits, show up here.'
                : 'Try another filter or search.',
          );
        } else {
          list = _InvoiceList(
            invoices: shown,
            selectedId: _selectedId,
            onTap: (i) =>
                setState(() => _selectedId = _selectedId == i.id ? null : i.id),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Glance(invoices: all ?? const []),
            const SizedBox(height: CruSpace.cardGap),
            DentalFilterBar(
              filters: [
                CruSegmentedControl<_InvoiceFilter>(
                  semanticLabel: 'Invoice status',
                  segments: [
                    for (final f in _InvoiceFilter.values)
                      CruSegment(f, f.label),
                  ],
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ],
              search: DentalSearchField(
                controller: _search,
                hint: 'Search patient, service or invoice no.',
                onChanged: (_) => setState(() {}),
              ),
              trailing: [
                CruButton(
                  label: 'New invoice',
                  icon: CruIcons.plus,
                  kind: CruButtonKind.secondary,
                  onPressed: _newInvoice,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.cardGap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: list),
                  const SizedBox(width: CruSpace.cardGap),
                  SizedBox(
                    width: CruSize.rightColumn,
                    child: selected == null
                        ? const _MessageCard(
                            icon: CruIcons.fileText,
                            title: 'Select an invoice',
                            body: 'Its details and actions show here.',
                          )
                        : _InvoiceDetails(
                            invoice: selected,
                            onClose: () => setState(() => _selectedId = null),
                            onViewPdf: () => _viewPdf(selected!),
                            onEdit: () => _edit(selected!),
                            onCancel: () => _cancel(selected!),
                            onMarkPaid: () => _repository.updateInvoiceStatus(
                              selected!.id,
                              'Paid',
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

String _patient(InvoiceModel i) =>
    i.patientName.trim().isEmpty ? 'No patient' : i.patientName.trim();

String _date(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// The status pill: green once paid, amber while it waits, grey for cancelled.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.invoice});

  final InvoiceModel invoice;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (invoice.isCancelled) {
      return CruPill(
        text: 'Cancelled',
        background: c.track,
        foreground: c.label2,
      );
    }
    final paid = invoice.isPaid;
    return CruPill(
      text: invoice.isOverdue
          ? 'Overdue'
          : paid
          ? 'Paid'
          : 'Pending',
      background: paid ? c.greenTint : c.amberTint,
      foreground: paid ? c.greenText : c.amberText,
    );
  }
}

/// Invoiced, collected, awaiting and overdue totals (skips cancelled invoices).
class _Glance extends StatelessWidget {
  const _Glance({required this.invoices});

  final List<InvoiceModel> invoices;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final active = invoices.where((i) => !i.isCancelled).toList();
    double sum(bool Function(InvoiceModel) test) =>
        active.where(test).fold<double>(0, (total, i) => total + i.amount);
    int count(bool Function(InvoiceModel) test) => active.where(test).length;

    final overdue = count((i) => i.isOverdue);
    Widget cell(String label, double value, Widget caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlanceLabel(label),
        GlanceMetric(DashFormat.rupees(value)),
        GlanceCaption(caption),
      ],
    );

    return GlanceStrip(
      semanticLabel: 'Invoices at a glance',
      cells: [
        cell(
          'Invoiced',
          sum((_) => true),
          Text(DashFormat.plural(active.length, 'invoice')),
        ),
        cell(
          'Collected',
          sum((i) => i.isPaid),
          Text('${count((i) => i.isPaid)} paid'),
        ),
        cell(
          'Awaiting payment',
          sum((i) => i.isPending),
          Text('${count((i) => i.isPending)} pending'),
        ),
        cell(
          'Overdue',
          sum((i) => i.isOverdue),
          overdue > 0
              ? Text(
                  '${DashFormat.plural(overdue, 'invoice')} past due',
                  style: TextStyle(color: c.amberText),
                )
              : const Text('Nothing past due'),
        ),
      ],
    );
  }
}

/// The invoices in one card: a column header, then one row each.
class _InvoiceList extends StatelessWidget {
  const _InvoiceList({
    required this.invoices,
    required this.selectedId,
    required this.onTap,
  });

  final List<InvoiceModel> invoices;
  final String? selectedId;
  final ValueChanged<InvoiceModel> onTap;

  static const _flex = [3, 5, 4, 3, 3, 3];

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final label = CruType.groupLabel.tint(c.label3);
    return CruCard(
      semanticLabel: 'Invoices',
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s12,
              CruSpace.s4,
              CruSpace.s12,
              CruSpace.s8,
            ),
            child: Row(
              children: [
                for (final (i, t) in const [
                  'Invoice',
                  'Patient',
                  'Service',
                  'Amount',
                  'Date',
                  'Status',
                ].indexed)
                  Expanded(
                    flex: _flex[i],
                    child: Text(t, style: label),
                  ),
              ],
            ),
          ),
          const CruSeparator(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: CruSpace.s4),
              itemCount: invoices.length,
              separatorBuilder: (_, _) => const CruSeparator(
                indent: CruSpace.s12,
                endIndent: CruSpace.s12,
              ),
              itemBuilder: (context, i) => _InvoiceRow(
                invoice: invoices[i],
                selected: invoices[i].id == selectedId,
                onTap: () => onTap(invoices[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.selected,
    required this.onTap,
  });

  final InvoiceModel invoice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    const flex = _InvoiceList._flex;
    Widget cell(int i, Widget child) => Expanded(flex: flex[i], child: child);
    Text text(String s, TextStyle style) =>
        Text(s, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);

    final displayNo = invoice.invoiceNumber.isNotEmpty
        ? invoice.invoiceNumber
        : invoice.id;

    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel:
          '$displayNo, ${_patient(invoice)}, '
          '${DashFormat.rupees(invoice.amount)}, ${invoice.status}',
      builder: (context, hovered) => DecoratedBox(
        decoration: ShapeDecoration(
          color: selected
              ? c.accentWash
              : hovered
              ? c.inset
              : c.inset.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s12,
            vertical: CruSpace.s14,
          ),
          child: Row(
            children: [
              cell(0, text(displayNo, CruType.callout.tabular.tint(c.label2))),
              cell(1, text(_patient(invoice), CruType.row.tint(c.label))),
              cell(2, text(invoice.service, CruType.subhead.tint(c.label2))),
              cell(
                3,
                text(
                  DashFormat.rupees(invoice.amount),
                  CruType.row.w600.tabular.tint(c.label),
                ),
              ),
              cell(
                4,
                text(
                  _date(invoice.date),
                  CruType.subhead.tabular.tint(c.label2),
                ),
              ),
              cell(
                5,
                Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(invoice: invoice),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected invoice: who, what, how much, when, its notes, and
/// View PDF / Edit / Cancel invoice / Mark as paid.
class _InvoiceDetails extends StatelessWidget {
  const _InvoiceDetails({
    required this.invoice,
    required this.onClose,
    required this.onViewPdf,
    required this.onEdit,
    required this.onCancel,
    required this.onMarkPaid,
  });

  final InvoiceModel invoice;
  final VoidCallback onClose;
  final VoidCallback onViewPdf;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final due = invoice.dueDate;
    final displayNo = invoice.invoiceNumber.isNotEmpty
        ? invoice.invoiceNumber
        : invoice.id;

    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: CruType.groupLabel.tint(c.label3)),
          const SizedBox(height: CruSpace.s4),
          Text(value, style: CruType.callout.tabular.tint(c.label)),
        ],
      ),
    );

    return CruCard(
      semanticLabel: 'Invoice $displayNo',
      padding: const EdgeInsets.all(CruSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayNo,
                  style: CruType.headline.tabular.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CruIconButton(
                icon: CruIcons.close,
                semanticLabel: 'Close invoice',
                size: CruSize.squareButton,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          Row(
            children: [
              Text(
                DashFormat.rupees(invoice.amount),
                style: CruType.amount.tabular.tint(c.label),
              ),
              const SizedBox(width: CruSpace.s12),
              _StatusPill(invoice: invoice),
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field('Patient', _patient(invoice)),
                  field('Service', invoice.service),
                  field('Date', _date(invoice.date)),
                  if (due != null) field('Due', _date(due)),
                  if (invoice.notes.trim().isNotEmpty)
                    field('Notes', invoice.notes.trim()),
                ],
              ),
            ),
          ),
          CruButton(
            label: 'View PDF',
            icon: CruIcons.fileText,
            expand: true,
            onPressed: onViewPdf,
          ),
          const SizedBox(height: CruSpace.s8),
          if (!invoice.isPaid && !invoice.isCancelled) ...[
            CruButton(
              label: 'Mark as paid',
              kind: CruButtonKind.inset,
              icon: CruIcons.check,
              expand: true,
              onPressed: onMarkPaid,
            ),
            const SizedBox(height: CruSpace.s8),
          ],
          if (!invoice.isCancelled) ...[
            CruButton(
              label: 'Edit',
              kind: CruButtonKind.inset,
              icon: CruIcons.pen,
              expand: true,
              onPressed: onEdit,
            ),
            const SizedBox(height: CruSpace.s8),
            CruButton(
              label: 'Cancel invoice',
              kind: CruButtonKind.inset,
              expand: true,
              onPressed: onCancel,
            ),
          ],
        ],
      ),
    );
  }
}

/// An icon, a title and a line, centred in a card (empty list, nothing
/// selected, load error).
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final CruIconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Center(
        child: SingleChildScrollView(
          child: DentalEmptyState(icon: icon, title: title, body: body),
        ),
      ),
    );
  }
}
