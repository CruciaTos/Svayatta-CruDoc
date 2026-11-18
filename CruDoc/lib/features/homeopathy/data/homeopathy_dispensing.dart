import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

/// How a remedy is supplied. The form fixes the unit, so a stock line and
/// the dispenses against it always count the same thing.
enum RemedyForm {
  pills('Pills', 'pills'),
  globules('Globules', 'dram'),
  liquid('Dilution / liquid', 'ml'),
  tablets('Tablets', 'tablets'),
  motherTincture('Mother tincture', 'ml'),
  powders('Powders / papers', 'doses');

  const RemedyForm(this.label, this.unit);
  final String label;
  final String unit;

  static RemedyForm fromName(String name) => RemedyForm.values.firstWhere(
    (f) => f.name == name,
    orElse: () => RemedyForm.pills,
  );
}

String _norm(String s) => s.trim().toLowerCase();

/// "Arnica montana 30C".
String remedyLabel(String remedy, String potency) =>
    [remedy.trim(), potency.trim()].where((s) => s.isNotEmpty).join(' ');

/// One remedy dispensed to a patient (record kind `homeoDispense`).
class RemedyDispense {
  const RemedyDispense(this.record);

  final DentalRecord record;

  String get id => record.id;
  String get remedy => record.str('remedy');
  String get potency => record.str('potency');
  RemedyForm get form => RemedyForm.fromName(record.str('form'));
  int get qty => record.integer('qty') ?? 0;
  String get unit => record.str('unit');
  String get note => record.str('note');
  DateTime get date => record.recordedAt;

  /// Stock line this dispense took from, and how much it actually took.
  String get stockId => record.str('stockId');
  int get stockTaken => record.integer('stockTaken') ?? 0;
}

/// One clinic stock line (record kind `homeoStock`).
class RemedyStockLine {
  const RemedyStockLine(this.record);

  final DentalRecord record;

  String get id => record.id;
  String get remedy => record.str('remedy');
  String get potency => record.str('potency');
  RemedyForm get form => RemedyForm.fromName(record.str('form'));
  int get qty => record.integer('qty') ?? 0;
  String get unit => form.unit;

  /// Low-stock level; null when not set.
  int? get lowLevel => record.integer('low');
  bool get isLow => lowLevel != null && qty <= lowLevel!;

  bool matches(String remedy, String potency, RemedyForm form) =>
      _norm(this.remedy) == _norm(remedy) &&
      _norm(this.potency) == _norm(potency) &&
      this.form == form;
}

/// A patient's dispenses, newest first.
final homeoDispensesProvider =
    Provider.family<AsyncValue<List<RemedyDispense>>, String>((ref, patientId) {
      final recs = ref.watch(
        patientRecordsProvider((
          patientId: patientId,
          kind: RecKind.homeoDispense,
        )),
      );
      return recs.whenData(
        (list) =>
            [for (final r in list) RemedyDispense(r)]
              ..sort((a, b) => b.date.compareTo(a.date)),
      );
    });

/// The clinic's remedy stock, A to Z.
final homeoStockProvider = Provider<AsyncValue<List<RemedyStockLine>>>((ref) {
  final recs = ref.watch(clinicRecordsProvider(RecKind.homeoStock));
  return recs.whenData(
    (list) =>
        [for (final r in list) RemedyStockLine(r)]
          ..sort((a, b) => _norm(a.remedy).compareTo(_norm(b.remedy))),
  );
});

Future<List<RemedyStockLine>> _freshStock(WidgetRef ref) async {
  final recs = await ref
      .read(dentalRecordsRepoProvider)
      .all(ref.read(dentalDoctorIdProvider), RecKind.homeoStock);
  return [for (final r in recs) RemedyStockLine(r)];
}

/// Saves a dispense. If a stock line exists for the same remedy, potency
/// and form, it is reduced (never below zero) and the dispense remembers how
/// much it took. With no stock line the dispense is just logged.
Future<void> dispenseRemedy(
  WidgetRef ref, {
  required String patientId,
  required String remedy,
  required String potency,
  required RemedyForm form,
  required int qty,
  required String note,
}) async {
  final stock = (await _freshStock(
    ref,
  )).where((s) => s.matches(remedy, potency, form)).firstOrNull;
  var taken = 0;
  if (stock != null) {
    taken = qty < stock.qty ? qty : stock.qty;
    await saveDentalRecord(
      ref,
      stock.record.copyWith(
        data: {...stock.record.data, 'qty': stock.qty - taken},
      ),
    );
  }
  await saveDentalRecord(
    ref,
    DentalRecord.create(patientId, RecKind.homeoDispense, {
      'remedy': remedy.trim(),
      'potency': potency.trim(),
      'form': form.name,
      'qty': qty,
      'unit': form.unit,
      'note': note.trim(),
      if (stock != null) 'stockId': stock.id,
      if (stock != null) 'stockTaken': taken,
    }),
  );
}

/// Deletes a dispense and gives back what it took from stock (when that
/// stock line still exists).
Future<void> deleteDispense(WidgetRef ref, RemedyDispense d) async {
  if (d.stockId.isNotEmpty && d.stockTaken > 0) {
    final stock = (await _freshStock(
      ref,
    )).where((s) => s.id == d.stockId).firstOrNull;
    if (stock != null) {
      await saveDentalRecord(
        ref,
        stock.record.copyWith(
          data: {...stock.record.data, 'qty': stock.qty + d.stockTaken},
        ),
      );
    }
  }
  await deleteDentalRecord(ref, d.record);
}

/// Adds [qty] to the matching stock line, or starts a new one.
Future<void> addRemedyStock(
  WidgetRef ref, {
  required String remedy,
  required String potency,
  required RemedyForm form,
  required int qty,
}) async {
  final existing = (await _freshStock(
    ref,
  )).where((s) => s.matches(remedy, potency, form)).firstOrNull;
  if (existing != null) {
    await saveDentalRecord(
      ref,
      existing.record.copyWith(
        data: {...existing.record.data, 'qty': existing.qty + qty},
      ),
    );
    return;
  }
  await saveDentalRecord(
    ref,
    DentalRecord.create('', RecKind.homeoStock, {
      'remedy': remedy.trim(),
      'potency': potency.trim(),
      'form': form.name,
      'qty': qty,
      'unit': form.unit,
    }),
  );
}

/// Sets the quantity on hand and the optional low-stock level.
Future<void> updateRemedyStock(
  WidgetRef ref,
  RemedyStockLine line, {
  required int qty,
  required int? low,
}) async {
  final data = {...line.record.data, 'qty': qty};
  if (low == null) {
    data.remove('low');
  } else {
    data['low'] = low;
  }
  await saveDentalRecord(ref, line.record.copyWith(data: data));
}

Future<void> deleteRemedyStock(WidgetRef ref, RemedyStockLine line) =>
    deleteDentalRecord(ref, line.record);
