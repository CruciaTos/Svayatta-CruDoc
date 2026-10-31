import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_bill.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';

/// Every bill (the stream the Invoices screen reads).
final invoicesStreamProvider = StreamProvider<List<InvoiceModel>>((ref) {
  ref.watch(authStateProvider);
  return InvoiceRepository().watchInvoices();
});

/// One bill as Payments shows it, in rupees.
class PatientBill {
  const PatientBill({
    required this.invoice,
    required this.paid,
    required this.balance,
  });

  final InvoiceModel invoice;
  final double paid;

  /// What is still owed on it (0 when paid or cancelled).
  final double balance;

  bool get partPaid => paid > 0 && balance > 0;

  static PatientBill of(InvoiceModel inv) {
    if (inv.isCancelled) {
      return PatientBill(invoice: inv, paid: 0, balance: 0);
    }
    final bill = inv.bill;
    // Older bills have no line items: their status is all there is.
    if (bill.items.isEmpty) {
      return PatientBill(
        invoice: inv,
        paid: inv.isPaid ? inv.amount : 0,
        balance: inv.isPaid ? 0 : inv.amount,
      );
    }
    final totals = InvoiceTotals.of(bill);
    return PatientBill(
      invoice: inv,
      paid: totals.paid / 100,
      balance: totals.balance > 0 ? totals.balance / 100 : 0,
    );
  }
}

/// A patient's money, from the records Revenue and Invoices use: their
/// bills, the payments received (income entries) and the fees still owed
/// (pending payments). A list is null while it loads.
class PatientBilling {
  const PatientBilling({
    required this.bills,
    required this.received,
    required this.unpaid,
  });

  /// Newest first, cancelled ones included.
  final List<PatientBill>? bills;

  /// Newest first.
  final List<RevenueEntry>? received;

  /// Oldest first.
  final List<PendingPayment>? unpaid;

  double get unpaidTotal =>
      (unpaid ?? const <PendingPayment>[]).fold(0, (s, p) => s + p.amount);

  /// Bills with something still owed on them.
  List<PatientBill> get openBills => [
    for (final b in bills ?? const <PatientBill>[])
      if (b.balance > 0) b,
  ];

  double get openBillsTotal => openBills.fold(0, (s, b) => s + b.balance);
}

/// [PatientBilling] for one patient.
final patientBillingProvider = Provider.family<PatientBilling, String>((
  ref,
  patientId,
) {
  final invoices = ref.watch(invoicesStreamProvider);
  final entries = ref.watch(recentRevenueEntriesProvider);
  final pending = ref.watch(pendingPaymentsProvider);
  final invoiceList = invoices.hasError
      ? const <InvoiceModel>[]
      : invoices.value;
  final entryList = entries.hasError ? const <RevenueEntry>[] : entries.value;
  final pendingList = pending.hasError
      ? const <PendingPayment>[]
      : pending.value;
  return PatientBilling(
    bills: invoiceList == null
        ? null
        : ([
            for (final inv in invoiceList)
              if (inv.patientId == patientId) PatientBill.of(inv),
          ]..sort((a, b) => b.invoice.date.compareTo(a.invoice.date))),
    received: entryList == null
        ? null
        : ([
            for (final e in entryList)
              if (e.patientId == patientId &&
                  !e.isDeleted &&
                  e.kind == TransactionKind.income &&
                  e.amount > 0)
                e,
          ]..sort((a, b) => b.date.compareTo(a.date))),
    unpaid: pendingList == null
        ? null
        : ([
            for (final p in pendingList)
              if (p.patientId == patientId && !p.isPaid && p.amount > 0) p,
          ]..sort((a, b) => a.date.compareTo(b.date))),
  );
});
