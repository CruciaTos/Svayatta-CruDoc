import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/pdf/presentation/medical_pdf_preview_screen.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/revenue/data/invoice_pdf_mapper.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Invoices on the phone: what is still owed, then every invoice with
/// its state. Tap one to view PDF, edit, mark it paid, or cancel it.
class MobileInvoicesScreen extends StatefulWidget {
  const MobileInvoicesScreen({super.key});

  @override
  State<MobileInvoicesScreen> createState() => _MobileInvoicesScreenState();
}

class _MobileInvoicesScreenState extends State<MobileInvoicesScreen> {
  final _repo = InvoiceRepository();
  final _search = TextEditingController();
  late final Stream<List<InvoiceModel>> _stream = _repo.watchInvoices();

  static const _filters = ['All', 'Pending', 'Overdue', 'Paid'];
  String _filter = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static double _sum(Iterable<InvoiceModel> l) =>
      l.fold(0.0, (s, i) => s + i.amount);

  void _new() => showDesktopCreateInvoiceDialog(mobileRoot(context));

  bool _matches(InvoiceModel i) {
    if (_filter != 'All' && i.status.toLowerCase() != _filter.toLowerCase()) {
      return false;
    }
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty ||
        i.patientName.toLowerCase().contains(q) ||
        i.service.toLowerCase().contains(q) ||
        i.id.toLowerCase().contains(q) ||
        i.invoiceNumber.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceModel>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data;
        final owed = all == null
            ? 0.0
            : _sum(all.where((i) => !i.isPaid && !i.isCancelled));
        final shown = all == null
            ? const <InvoiceModel>[]
            : all.where(_matches).toList();

        int count(String f) => all == null
            ? 0
            : f == 'All'
            ? all.length
            : all
                  .where((i) =>
                      !i.isCancelled &&
                      i.status.toLowerCase() == f.toLowerCase())
                  .length;

        return ListView(
          padding: EdgeInsets.only(
            bottom: MobileMetrics.navBottom(context) + CruSpace.s24,
          ),
          children: [
            MobileHeader(
              pushed: true,
              title: 'Invoices',
              subtitle: all == null
                  ? null
                  : all.isEmpty
                  ? 'Bills you raise show here'
                  : owed > 0
                  ? '${DashFormat.rupees(owed)} still to collect'
                  : 'Everything is paid',
              trailing: MobileCircleButton(
                icon: CruIcons.plus,
                semanticLabel: 'New invoice',
                onPressed: _new,
              ),
            ),
            const SizedBox(height: CruSpace.s16),
            if (all == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
                child: MobileCard(child: MobileLoading('Loading invoices…')),
              )
            else if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: MobileEmpty(
                  icon: CruIcons.fileText,
                  title: 'No invoices yet',
                  body:
                      'Raise one after a visit and it waits here until it '
                      'is paid.',
                  action: 'New invoice',
                  onAction: _new,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: _Totals(
                  paid: _sum(all.where((i) => i.isPaid && !i.isCancelled)),
                  pending: _sum(all.where((i) => i.isPending && !i.isCancelled)),
                  overdue: _sum(all.where((i) => i.isOverdue && !i.isCancelled)),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: MobileSearchField(
                  controller: _search,
                  hint: 'Search patient, service or no.',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: MobileSegmented<String>(
                  values: _filters,
                  label: (f) => f == 'All' ? f : '$f (${count(f)})',
                  selected: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MobileMetrics.gutter,
                  ),
                  child: MobileEmpty(
                    icon: CruIcons.search,
                    title: 'No invoices match',
                    body: 'Try a different filter or search term.',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MobileMetrics.gutter,
                  ),
                  child: MobileCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const Divider(height: 1, thickness: 0.5),
                          _InvoiceRow(invoice: shown[i], repo: _repo),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.paid,
    required this.pending,
    required this.overdue,
  });

  final double paid;
  final double pending;
  final double overdue;

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Row(
        children: [
          Expanded(
            child: _TotalTile(
              label: 'Paid',
              value: paid,
              tone: MobileTone.green,
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: _TotalTile(
              label: 'Pending',
              value: pending,
              tone: MobileTone.blue,
            ),
          ),
          if (overdue > 0) ...[
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: _TotalTile(
                label: 'Overdue',
                value: overdue,
                tone: MobileTone.amber,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final double value;
  final MobileTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final color = switch (tone) {
      MobileTone.green => c.greenText,
      MobileTone.amber => c.amberText,
      MobileTone.blue => c.accent,
      _ => c.label,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: MobileType.caption.tint(c.label3)),
        const SizedBox(height: CruSpace.s2),
        Text(
          DashFormat.rupees(value),
          style: MobileType.headline.tabular.tint(color),
        ),
      ],
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice, required this.repo});

  final InvoiceModel invoice;
  final InvoiceRepository repo;

  MobileTone get _tone => invoice.isCancelled
      ? MobileTone.slate
      : (invoice.isPaid
          ? MobileTone.green
          : invoice.isOverdue
          ? MobileTone.amber
          : MobileTone.blue);

  bool get _sample => invoice.doctorId == 'sample';

  Future<void> _set(String status) async {
    if (_sample) return;
    await repo.updateInvoiceStatus(invoice.id, status);
  }

  Future<void> _viewPdf(BuildContext context) async {
    Patient? patient;
    if (invoice.patientId != null && invoice.patientId!.isNotEmpty) {
      try {
        final patients = await PatientRepository().watchPatients().first;
        patient = patients.where((p) => p.id == invoice.patientId).firstOrNull;
      } catch (_) {}
    }

    if (!context.mounted) return;
    await MedicalPdfPreviewScreen.open(
      context,
      documentData: invoicePdfData(invoice, patient: patient),
      invoice: invoice,
    );
  }

  void _sheet(BuildContext context) {
    final i = invoice;
    final displayNo = i.invoiceNumber.isNotEmpty ? i.invoiceNumber : i.id;

    showMobileActionSheet(
      context,
      title: i.patientName.isEmpty ? displayNo : i.patientName,
      subtitle: '$displayNo · ${DashFormat.rupees(i.amount)} · ${i.service}',
      leading: MobileIconTile(icon: CruIcons.fileText, tone: _tone),
      actions: [
        MobileSheetAction(
          label: 'View PDF',
          icon: CruIcons.fileText,
          tone: MobileTone.blue,
          onTap: () => _viewPdf(context),
        ),
        if (!i.isCancelled) ...[
          MobileSheetAction(
            label: 'Edit',
            icon: CruIcons.pen,
            tone: MobileTone.blue,
            onTap: () {
              showDesktopCreateInvoiceDialog(
                context,
                initialInvoice: i,
              );
            },
          ),
          if (!i.isPaid)
            MobileSheetAction(
              label: 'Mark paid',
              icon: CruIcons.check,
              tone: MobileTone.green,
              onTap: () => _set('Paid'),
            ),
          if (!i.isPending)
            MobileSheetAction(
              label: i.isPaid ? 'Mark not paid' : 'Mark pending',
              icon: CruIcons.clock,
              tone: MobileTone.blue,
              onTap: () => _set('Pending'),
            ),
          if (!i.isOverdue && !i.isPaid)
            MobileSheetAction(
              label: 'Mark overdue',
              icon: CruIcons.warning,
              tone: MobileTone.amber,
              onTap: () => _set('Overdue'),
            ),
          MobileSheetAction(
            label: 'Cancel invoice',
            icon: CruIcons.close,
            destructive: true,
            onTap: () => _confirmCancel(context),
          ),
        ],
      ],
    );
  }

  void _confirmCancel(BuildContext context) {
    final displayNo =
        invoice.invoiceNumber.isNotEmpty ? invoice.invoiceNumber : invoice.id;
    showMobileActionSheet(
      context,
      title: 'Cancel invoice $displayNo?',
      subtitle:
          'It stays in your records with its number, marked cancelled, and leaves your revenue.',
      actions: [
        MobileSheetAction(
          label: 'Cancel invoice',
          icon: CruIcons.close,
          destructive: true,
          onTap: () async {
            if (!_sample) await repo.cancelInvoice(invoice.id);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final i = invoice;
    final displayNo = i.invoiceNumber.isNotEmpty ? i.invoiceNumber : i.id;

    return MobileRow(
      leading: MobileIconTile(icon: CruIcons.fileText, tone: _tone),
      title: i.patientName.isEmpty ? 'Unnamed patient' : i.patientName,
      subtitle: [
        displayNo,
        if (i.service.trim().isNotEmpty) i.service.trim(),
        DashFormat.shortDate(i.date),
      ].join(' · '),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DashFormat.rupees(i.amount),
            style: MobileType.callout.tabular.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s4),
          MobilePill(i.status, tone: _tone),
        ],
      ),
      onTap: () => _sheet(context),
      onLongPress: () => _sheet(context),
    );
  }
}
