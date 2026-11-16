import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/ai_tools/core/ai_tool.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_billing_provider.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_bill.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';

const _maxItems = 15;
const _currency = 'INR';
const _modes = ['cash', 'upi', 'card', 'bank', 'other'];
const _invoiceStatuses = ['paid', 'pending', 'overdue', 'cancelled'];

String? _str(Map<String, Object?> a, String k) {
  final v = a[k];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

double? _num(Map<String, Object?> a, String k) {
  final v = a[k];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

DateTime? _date(Map<String, Object?> a, String k) {
  final s = _str(a, k);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

int _paise(double rupees) => (rupees * 100).round();

String _rupees(double v) {
  final whole = v == v.roundToDouble();
  return '₹${whole ? v.round().toString() : v.toStringAsFixed(2)}';
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, Object?> _invoiceRow(InvoiceModel inv) {
  final b = PatientBill.of(inv);
  return {
    'invoiceId': inv.id,
    'number': inv.invoiceNumber,
    'patientId': inv.patientId,
    'patient': inv.patientName,
    'date': _day(inv.date),
    'status': inv.status.toLowerCase(),
    'total': inv.amount,
    'paid': b.paid,
    'balance': b.balance,
    'currency': _currency,
  };
}

List<AiTool> billingTools() => [
  AiTool(
    name: 'get_patient_dues',
    description:
        'What one patient still owes: open invoices with balances and unpaid '
        'visit fees. Use before taking a payment.',
    group: AiToolGroup.billing,
    risk: AiToolRisk.read,
    permission: ClinicPermission.billing,
    params: const {'patientId': AiParam.string('Patient ID from find_patient')},
    run: (ctx, args) async {
      final id = _str(args, 'patientId');
      if (id == null) return AiToolResult.error('patientId is required.');
      await ctx.read(invoicesStreamProvider.future);
      await ctx.read(recentRevenueEntriesProvider.future);
      await ctx.read(pendingPaymentsProvider.future);
      final b = ctx.read(patientBillingProvider(id));
      final open = b.openBills.take(_maxItems).map((p) => _invoiceRow(p.invoice)).toList();
      final unpaid = (b.unpaid ?? const <PendingPayment>[])
          .take(_maxItems)
          .map(
            (p) => {
              'pendingPaymentId': p.id,
              'visitId': p.visitId,
              'description': p.description,
              'date': _day(p.date),
              'amount': p.amount,
            },
          )
          .toList();
      final total = b.openBillsTotal + b.unpaidTotal;
      return AiToolResult.ok(
        {
          'patientId': id,
          'totalDue': total,
          'openInvoicesTotal': b.openBillsTotal,
          'unpaidVisitFeesTotal': b.unpaidTotal,
          'currency': _currency,
          'openInvoices': open,
          'unpaidVisitFees': unpaid,
        },
        summary: total > 0 ? 'Owes ${_rupees(total)}' : 'Nothing owed',
      );
    },
  ),
  AiTool(
    name: 'list_pending_payments',
    description: 'Unpaid visit fees across all patients, oldest first (max 15).',
    group: AiToolGroup.billing,
    risk: AiToolRisk.read,
    permission: ClinicPermission.billing,
    run: (ctx, args) async {
      final all = await ctx.read(pendingPaymentsProvider.future);
      final list = [
        for (final p in all)
          if (!p.isPaid && p.amount > 0) p,
      ]..sort((a, b) => a.date.compareTo(b.date));
      final total = list.fold<double>(0, (s, p) => s + p.amount);
      return AiToolResult.ok(
        {
          'count': list.length,
          'total': total,
          'currency': _currency,
          'payments': [
            for (final p in list.take(_maxItems))
              {
                'pendingPaymentId': p.id,
                'patientId': p.patientId,
                'patient': p.payer,
                'visitId': p.visitId,
                'description': p.description,
                'date': _day(p.date),
                'amount': p.amount,
              },
          ],
        },
        summary: '${list.length} unpaid, ${_rupees(total)}',
      );
    },
  ),
  AiTool(
    name: 'list_invoices',
    description:
        'Invoices, newest first (max 15). Filter by patient, date range and status.',
    group: AiToolGroup.billing,
    risk: AiToolRisk.read,
    permission: ClinicPermission.billing,
    params: const {
      'patientId': AiParam.string('Only this patient', required: false),
      'from': AiParam.date('Earliest invoice date', required: false),
      'to': AiParam.date('Latest invoice date', required: false),
      'status': AiParam.enumOf(
        _invoiceStatuses,
        'Invoice status',
        required: false,
      ),
    },
    run: (ctx, args) async {
      final all = await ctx.read(invoicesStreamProvider.future);
      final pid = _str(args, 'patientId');
      final from = _date(args, 'from');
      final to = _date(args, 'to');
      final status = _str(args, 'status');
      final list = [
        for (final i in all)
          if ((pid == null || i.patientId == pid) &&
              (from == null || !i.date.isBefore(from)) &&
              (to == null ||
                  i.date.isBefore(to.add(const Duration(days: 1)))) &&
              (status == null || i.status.toLowerCase() == status))
            i,
      ]..sort((a, b) => b.date.compareTo(a.date));
      return AiToolResult.ok(
        {
          'count': list.length,
          'shown': list.length > _maxItems ? _maxItems : list.length,
          'invoices': list.take(_maxItems).map(_invoiceRow).toList(),
        },
        summary: '${list.length} invoice(s)',
      );
    },
  ),
  AiTool(
    name: 'get_invoice',
    description: 'One invoice with its line items, totals and balance.',
    group: AiToolGroup.billing,
    risk: AiToolRisk.read,
    permission: ClinicPermission.billing,
    params: const {'invoiceId': AiParam.string('Invoice ID')},
    run: (ctx, args) async {
      final id = _str(args, 'invoiceId');
      if (id == null) return AiToolResult.error('invoiceId is required.');
      final all = await ctx.read(invoicesStreamProvider.future);
      final inv = all.where((i) => i.id == id).firstOrNull;
      if (inv == null) return AiToolResult.error('No invoice with id $id.');
      final bill = inv.bill;
      return AiToolResult.ok({
        ..._invoiceRow(inv),
        'dueDate': inv.dueDate == null ? null : _day(inv.dueDate!),
        'notes': inv.notes,
        'discount': bill.discountPaise / 100,
        'paymentMode': bill.paymentMode,
        'items': [
          for (final i in bill.items.take(_maxItems))
            {
              'name': i.name,
              'qty': i.qty,
              'rate': i.ratePaise / 100,
              'taxPercent': i.taxPct,
            },
        ],
      });
    },
  ),
  AiTool(
    name: 'draft_invoice',
    description:
        'Create an UNPAID invoice for a patient from line items. Never marks '
        'it paid; use record_payment afterwards. Pass patientName (from '
        'find_patient) so the confirm card can show it.',
    group: AiToolGroup.billing,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.billing,
    params: const {
      'patientId': AiParam.string('Patient ID from find_patient'),
      'patientName': AiParam.string('Patient full name'),
      'items': AiParam.list(
        AiParam.object({
          'name': AiParam.string('Item or procedure name'),
          'qty': AiParam.integer('Quantity', min: 1),
          'rate': AiParam.number('Price per unit in rupees', min: 0),
          'taxPercent': AiParam.number('Tax percent', required: false),
        }, 'Line item'),
        'Line items',
      ),
      'discount': AiParam.number('Discount in rupees', required: false),
    },
    confirmText: (a) {
      final items = a['items'] is List ? a['items'] as List : const [];
      var total = 0.0;
      for (final i in items) {
        if (i is Map) {
          final q = (i['qty'] as num?)?.toDouble() ?? 1;
          final r = (i['rate'] as num?)?.toDouble() ?? 0;
          final t = (i['taxPercent'] as num?)?.toDouble() ?? 0;
          total += q * r * (1 + t / 100);
        }
      }
      total -= (a['discount'] as num?)?.toDouble() ?? 0;
      final who = _str(a, 'patientName') ?? 'this patient';
      return 'Create an unpaid invoice of about '
          '${_rupees(total < 0 ? 0 : total)} for $who?';
    },
    run: (ctx, args) async {
      final pid = _str(args, 'patientId');
      if (pid == null) return AiToolResult.error('patientId is required.');
      final name = _str(args, 'patientName');
      if (name == null) return AiToolResult.error('patientName is required.');
      final raw = args['items'];
      if (raw is! List || raw.isEmpty) {
        return AiToolResult.error('At least one line item is required.');
      }
      final items = <InvoiceBillItem>[];
      for (final r in raw) {
        if (r is! Map) continue;
        final itemName = (r['name'] as String?)?.trim() ?? '';
        final qty = (r['qty'] as num?)?.toInt() ?? 1;
        final rate = (r['rate'] as num?)?.toDouble();
        if (itemName.isEmpty || rate == null || rate < 0 || qty < 1) {
          return AiToolResult.error(
            'Each item needs a name, qty of 1 or more and a rate.',
          );
        }
        items.add(
          InvoiceBillItem(
            name: itemName,
            qty: qty,
            ratePaise: _paise(rate),
            taxPct: (r['taxPercent'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
      if (items.isEmpty) {
        return AiToolResult.error('At least one valid line item is required.');
      }
      final discount = _num(args, 'discount') ?? 0;
      if (discount < 0) {
        return AiToolResult.error('Discount cannot be negative.');
      }
      final bill = InvoiceBill(items: items, discountPaise: _paise(discount));
      final totals = InvoiceTotals.of(bill);
      if (totals.grand <= 0) {
        return AiToolResult.error('Invoice total must be above zero.');
      }
      final repo = InvoiceRepository();
      try {
        final inv = await repo.createBilledInvoice(
          patientName: name,
          patientId: pid,
          bill: bill,
          date: DateTime.now(),
        );
        return AiToolResult.ok(
          {
            'invoiceId': inv.id,
            'number': inv.invoiceNumber,
            'status': inv.status.toLowerCase(),
            'total': totals.grand / 100,
            'currency': _currency,
          },
          summary:
              'Invoice ${inv.invoiceNumber} for ${_rupees(totals.grand / 100)} created, unpaid',
          undo: () => repo.cancelInvoice(inv.id),
        );
      } catch (e) {
        return AiToolResult.error("Couldn't create the invoice: $e");
      }
    },
  ),
  AiTool(
    name: 'record_payment',
    description:
        'Record money received. Give exactly one of visitId, '
        'pendingPaymentId or invoiceId. Visit and pending-payment fees are '
        'taken in full; invoices accept part payments up to the balance. '
        'Pass patientName so the confirm card can show it.',
    group: AiToolGroup.billing,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.billing,
    params: const {
      'visitId': AiParam.string('Visit ID', required: false),
      'pendingPaymentId': AiParam.string(
        'Pending payment ID from list_pending_payments',
        required: false,
      ),
      'invoiceId': AiParam.string('Invoice ID', required: false),
      'amount': AiParam.number('Amount in rupees', min: 0),
      'mode': AiParam.enumOf(_modes, 'Payment mode'),
      'patientName': AiParam.string('Patient full name', required: false),
    },
    confirmText: (a) {
      final amt = (a['amount'] as num?)?.toDouble() ?? 0;
      final mode = _str(a, 'mode');
      final who = _str(a, 'patientName');
      final modeText = mode == null ? '' : ' ${mode == 'upi' ? 'UPI' : mode}';
      return 'Record ${_rupees(amt)}$modeText payment'
          '${who == null ? '' : ' from $who'}?';
    },
    run: (ctx, args) async {
      final visitId = _str(args, 'visitId');
      final pendingId = _str(args, 'pendingPaymentId');
      final invoiceId = _str(args, 'invoiceId');
      final given = [visitId, pendingId, invoiceId].whereType<String>().length;
      if (given != 1) {
        return AiToolResult.error(
          'Give exactly one of visitId, pendingPaymentId or invoiceId.',
        );
      }
      final amount = _num(args, 'amount');
      if (amount == null || amount <= 0) {
        return AiToolResult.error('amount must be above zero.');
      }
      final mode = _str(args, 'mode');
      if (mode == null || !_modes.contains(mode)) {
        return AiToolResult.error('mode must be one of ${_modes.join(', ')}.');
      }
      try {
        if (visitId != null) {
          await ctx
              .read(visitRepositoryProvider)
              .recordPayment(visitId, amount: amount);
          return AiToolResult.ok({
            'visitId': visitId,
            'recorded': amount,
            'mode': mode,
            'currency': _currency,
            'note': 'Payment mode is not stored for visit payments.',
          }, summary: '${_rupees(amount)} recorded');
        }
        if (pendingId != null) {
          final pending = await ctx
              .read(revenueRepositoryProvider)
              .getPendingPayment(pendingId);
          if (pending == null || pending.isPaid) {
            return AiToolResult.error('No unpaid pending payment $pendingId.');
          }
          if ((pending.amount - amount).abs() > 0.009) {
            return AiToolResult.error(
              'This fee is ${_rupees(pending.amount)} and is taken in full. '
              'Use the exact amount.',
              data: {'amountDue': pending.amount, 'currency': _currency},
            );
          }
          await ctx
              .read(visitRepositoryProvider)
              .markVisitationPaymentPaid(pendingId);
          return AiToolResult.ok({
            'pendingPaymentId': pendingId,
            'recorded': amount,
            'mode': mode,
            'currency': _currency,
            'note': 'Payment mode is not stored for visit fees.',
          }, summary: '${_rupees(amount)} recorded');
        }
        final all = await ctx.read(invoicesStreamProvider.future);
        final inv = all.where((i) => i.id == invoiceId).firstOrNull;
        if (inv == null) return AiToolResult.error('No invoice $invoiceId.');
        if (inv.isCancelled) {
          return AiToolResult.error('That invoice is cancelled.');
        }
        final before = PatientBill.of(inv);
        if (before.balance <= 0) {
          return AiToolResult.error('That invoice has no balance due.');
        }
        if (amount > before.balance + 0.009) {
          return AiToolResult.error(
            'Amount is more than the balance due.',
            data: {'balance': before.balance, 'currency': _currency},
          );
        }
        final newPaidPaise = _paise(before.paid + amount);
        final bill = inv.bill.items.isNotEmpty
            ? inv.bill.copyWith(paidPaise: newPaidPaise, paymentMode: mode)
            : InvoiceBill(
                items: [
                  InvoiceBillItem(
                    name: inv.service.isNotEmpty
                        ? inv.service
                        : 'Medical Consultation',
                    ratePaise: _paise(inv.amount),
                  ),
                ],
                paidPaise: newPaidPaise,
                paymentMode: mode,
                templateId: inv.bill.templateId,
                signedByUid: inv.bill.signedByUid,
              );
        final invRepo = InvoiceRepository();
        await invRepo.updateBilledInvoice(
          inv,
          patientName: inv.patientName,
          patientId: inv.patientId,
          bill: bill,
          date: inv.date,
          dueDate: inv.dueDate,
          notes: inv.notes,
          attendingDoctorUid: inv.attendingDoctorUid,
          invoiceNumber: inv.invoiceNumber,
        );
        final remaining = before.balance - amount;
        if (remaining <= 0.009) {
          await invRepo.updateInvoiceStatus(inv.id, 'Paid');
        }
        final now = DateTime.now();
        final no = inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : inv.id;
        await ctx
            .read(revenueRepositoryProvider)
            .createRevenueEntry(
              RevenueEntry(
                id: '',
                date: now,
                description:
                    'Invoice $no · ${inv.service.isNotEmpty ? inv.service : 'Payment'}',
                amount: amount,
                type: RevenueType.visit,
                payer: inv.patientName.isNotEmpty ? inv.patientName : null,
                patientId: inv.patientId,
                attendingDoctorUid: inv.attendingDoctorUid,
                createdAt: now,
                updatedAt: now,
              ),
            );
        return AiToolResult.ok({
          'invoiceId': inv.id,
          'recorded': amount,
          'mode': mode,
          'balanceAfter': remaining < 0 ? 0 : remaining,
          'currency': _currency,
        }, summary: '${_rupees(amount)} recorded on invoice $no');
      } catch (e) {
        return AiToolResult.error("Couldn't record the payment: $e");
      }
    },
  ),
  AiTool(
    name: 'cancel_invoice',
    description:
        'Cancel an invoice (kept on record, not deleted). Needs a reason.',
    group: AiToolGroup.billing,
    risk: AiToolRisk.confirm,
    permission: ClinicPermission.billing,
    params: const {
      'invoiceId': AiParam.string('Invoice ID'),
      'reason': AiParam.string('Why it is being cancelled'),
    },
    confirmText: (a) =>
        'Cancel invoice ${_str(a, 'invoiceId') ?? ''}? '
        'Reason: ${_str(a, 'reason') ?? 'not given'}',
    run: (ctx, args) async {
      final id = _str(args, 'invoiceId');
      if (id == null) return AiToolResult.error('invoiceId is required.');
      if (_str(args, 'reason') == null) {
        return AiToolResult.error('A reason is required.');
      }
      final all = await ctx.read(invoicesStreamProvider.future);
      final inv = all.where((i) => i.id == id).firstOrNull;
      if (inv == null) return AiToolResult.error('No invoice with id $id.');
      if (inv.isCancelled) {
        return AiToolResult.error('That invoice is already cancelled.');
      }
      try {
        await InvoiceRepository().cancelInvoice(id);
        return AiToolResult.ok({
          'invoiceId': id,
          'status': 'cancelled',
        }, summary: 'Invoice ${inv.invoiceNumber} cancelled');
      } catch (e) {
        return AiToolResult.error("Couldn't cancel the invoice: $e");
      }
    },
  ),
  AiTool(
    name: 'get_revenue_summary',
    description:
        'Money in and out for today, this week, this month, or a custom date range.',
    group: AiToolGroup.billing,
    risk: AiToolRisk.read,
    permission: ClinicPermission.revenue,
    params: const {
      'period': AiParam.enumOf(['today', 'week', 'month', 'custom'], 'Period'),
      'from': AiParam.date('Start, for custom', required: false),
      'to': AiParam.date('End inclusive, for custom', required: false),
    },
    run: (ctx, args) async {
      final entries = await ctx.read(recentRevenueEntriesProvider.future);
      final period = _str(args, 'period') ?? 'today';
      final DateSpan span;
      if (period == 'custom') {
        final from = _date(args, 'from');
        final to = _date(args, 'to');
        if (from == null || to == null || to.isBefore(from)) {
          return AiToolResult.error('Custom needs from and to (from <= to).');
        }
        span = DateSpan(from, to.add(const Duration(days: 1)));
      } else {
        final p = switch (period) {
          'week' => RevenuePeriod.week,
          'month' => RevenuePeriod.month,
          _ => RevenuePeriod.today,
        };
        span = RevenueBuilder.window(p, DateTime.now()).toDate;
      }
      final income = RevenueBuilder.sum(entries, span, TransactionKind.income);
      final expense = RevenueBuilder.sum(
        entries,
        span,
        TransactionKind.expense,
      );
      return AiToolResult.ok(
        {
          'period': period,
          'from': _day(span.start),
          'to': _day(span.end.subtract(const Duration(days: 1))),
          'collected': income,
          'expenses': expense,
          'net': income - expense,
          'currency': _currency,
        },
        summary: 'Collected ${_rupees(income)}',
      );
    },
  ),
  AiTool(
    name: 'get_recent_revenue',
    description: 'Most recent revenue entries, money in and out (max 15).',
    group: AiToolGroup.billing,
    risk: AiToolRisk.read,
    permission: ClinicPermission.revenue,
    params: const {
      'limit': AiParam.integer(
        'How many (default 10, max 15)',
        required: false,
        min: 1,
        max: 15,
      ),
    },
    run: (ctx, args) async {
      final all = await ctx.read(recentRevenueEntriesProvider.future);
      final n = (_num(args, 'limit') ?? 10).round().clamp(1, _maxItems);
      final list = [
        for (final e in all)
          if (!e.isDeleted) e,
      ]..sort((a, b) => b.date.compareTo(a.date));
      return AiToolResult.ok({
        'entries': [
          for (final e in list.take(n))
            {
              'entryId': e.id,
              'date': _day(e.date),
              'kind': e.kind.value,
              'amount': e.amount,
              'currency': _currency,
              'description': e.description,
              'payer': e.payer,
              'patientId': e.patientId,
            },
        ],
      });
    },
  ),
];
