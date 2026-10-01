import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Invoices on the phone: what is still owed, then every invoice with
/// its state. Tap one to mark it paid (or back), or delete it.
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
        i.service.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceModel>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data;
        final owed = all == null ? 0.0 : _sum(all.where((i) => !i.isPaid));
        final shown = all == null
            ? const <InvoiceModel>[]
            : all.where(_matches).toList();
        int count(String f) => all == null
            ? 0
            : f == 'All'
            ? all.length
            : all
                  .where((i) => i.status.toLowerCase() == f.toLowerCase())
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
                  paid: _sum(all.where((i) => i.isPaid)),
                  pending: _sum(all.where((i) => i.isPending)),
                  overdue: _sum(all.where((i) => i.isOverdue)),
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: MobileSearchField(
                  controller: _search,
                  hint: 'Search patient or service',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: CruSpace.s12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileMetrics.gutter,
                ),
                child: Row(
                  children: [
                    for (final f in _filters) ...[
                      MobileChip(
                        label: f,
                        count: count(f),
                        selected: _filter == f,
                        attention: f == 'Overdue' && count(f) > 0,
                        onTap: () => setState(() => _filter = f),
                      ),
                      const SizedBox(width: CruSpace.s8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              MobileRowGroup(
                children: shown.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(CruSpace.s20),
                          child: Text(
                            'No invoices match.',
                            textAlign: TextAlign.center,
                            style: MobileType.subhead.tint(context.cru.label2),
                          ),
                        ),
                      ]
                    : [
                        for (final i in shown)
                          _InvoiceRow(invoice: i, repo: _repo),
                      ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Paid, pending and overdue in one card.
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
    final c = context.cru;
    Widget figure(String label, double v, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: MobileType.caption.tint(c.label2)),
          const SizedBox(height: CruSpace.s4),
          Text(
            DashFormat.rupeesCompact(v),
            maxLines: 1,
            style: MobileType.title2.tabular.tint(color),
          ),
        ],
      ),
    );
    return MobileCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Row(
        children: [
          figure('Paid', paid, mobileTone(c, MobileTone.green).$2),
          figure('Pending', pending, c.label),
          figure(
            'Overdue',
            overdue,
            overdue > 0 ? mobileTone(c, MobileTone.amber).$2 : c.label,
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice, required this.repo});

  final InvoiceModel invoice;
  final InvoiceRepository repo;

  MobileTone get _tone => invoice.isPaid
      ? MobileTone.green
      : invoice.isOverdue
      ? MobileTone.amber
      : MobileTone.blue;

  bool get _sample => invoice.doctorId == 'sample';

  Future<void> _set(String status) async {
    if (_sample) return;
    await repo.updateInvoiceStatus(invoice.id, status);
  }

  void _sheet(BuildContext context) {
    final i = invoice;
    showMobileActionSheet(
      context,
      title: i.patientName.isEmpty ? 'Invoice' : i.patientName,
      subtitle: '${DashFormat.rupees(i.amount)} · ${i.service}',
      leading: MobileIconTile(icon: CruIcons.fileText, tone: _tone),
      actions: [
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
          label: 'Delete invoice',
          icon: CruIcons.close,
          destructive: true,
          onTap: () => _confirmDelete(context),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context) => showMobileActionSheet(
    context,
    title: 'Delete this invoice?',
    subtitle: 'It cannot be brought back.',
    actions: [
      MobileSheetAction(
        label: 'Delete',
        icon: CruIcons.close,
        destructive: true,
        onTap: () async {
          if (!_sample) await repo.deleteInvoice(invoice.id);
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final i = invoice;
    return MobileRow(
      leading: MobileIconTile(icon: CruIcons.fileText, tone: _tone),
      title: i.patientName.isEmpty ? 'Unnamed patient' : i.patientName,
      subtitle: [
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
