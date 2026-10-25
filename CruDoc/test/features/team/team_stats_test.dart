import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/team/domain/team_stats.dart';

final _from = DateTime(2026, 10, 1);
final _to = DateTime(2026, 11, 1);
final _in = DateTime(2026, 10, 10, 11);
final _before = DateTime(2026, 9, 20);

Visit _visit({
  String booker = 'front',
  String doctor = 'doc',
  VisitStatus status = VisitStatus.completed,
  DateTime? at,
  DateTime? created,
  bool deleted = false,
}) => Visit(
  id: 'v',
  patientId: 'p',
  scheduledStart: at ?? _in,
  durationMinutes: 15,
  address: '',
  status: status,
  createdAt: created ?? _in,
  updatedAt: at ?? _in,
  createdByUid: booker,
  attendingDoctorUid: doctor,
  isDeleted: deleted,
);

void main() {
  test('booking and attending a visit count for different people', () {
    final s = TeamStats.compute(
      from: _from,
      to: _to,
      visits: [
        _visit(),
        _visit(status: VisitStatus.scheduled),
        _visit(status: VisitStatus.cancelled),
        _visit(deleted: true),
      ],
    );
    expect(s.of('front').booked, 3);
    expect(s.of('front').attended, 0);
    expect(s.of('doc').attended, 2);
    expect(s.of('doc').completed, 1);
    expect(s.clinic.booked, 3);
    expect(s.clinic.completed, 1);
  });

  test('a visit booked last month for this month counts as attended only', () {
    final s = TeamStats.compute(
      from: _from,
      to: _to,
      visits: [_visit(created: _before)],
    );
    expect(s.of('front').booked, 0);
    expect(s.of('doc').attended, 1);
  });

  test(
    'money: income only, by whoever recorded it; invoices not cancelled',
    () {
      RevenueEntry entry(double amount, TransactionKind kind) => RevenueEntry(
        id: 'r',
        date: _in,
        description: '',
        amount: amount,
        type: RevenueType.visit,
        kind: kind,
        createdByUid: 'front',
        createdAt: _in,
        updatedAt: _in,
      );
      InvoiceModel invoice(String status) => InvoiceModel(
        id: 'i',
        doctorId: 'clinic',
        patientName: '',
        service: '',
        amount: 500,
        status: status,
        date: _in,
        createdByUid: 'front',
        createdAt: _in,
        updatedAt: _in,
      );
      final s = TeamStats.compute(
        from: _from,
        to: _to,
        revenue: [
          entry(800, TransactionKind.income),
          entry(300, TransactionKind.expense),
        ],
        invoices: [invoice('Paid'), invoice('Cancelled')],
      );
      expect(s.of('front').collected, 800);
      expect(s.of('front').invoices, 1);
      expect(s.clinic.collected, 800);
    },
  );

  test('records opened, files, check-ins and last activity', () {
    final later = DateTime(2026, 10, 20, 9);
    final s = TeamStats.compute(
      from: _from,
      to: _to,
      queue: [
        QueueEntry(
          id: 'q',
          tokenNumber: 1,
          queueDate: '2026-10-10',
          status: QueueStatus.completed,
          checkedInAt: _in,
          createdAt: _in,
          updatedAt: _in,
          createdByUid: 'front',
        ),
      ],
      logs: [
        TeamLogEntry(actorUid: 'doc', action: 'patient.view', at: _in),
        TeamLogEntry(actorUid: 'doc', action: 'patient.view', at: later),
        TeamLogEntry(actorUid: 'doc', action: 'file.download', at: _in),
        TeamLogEntry(actorUid: 'doc', action: 'team.update', at: _in),
        TeamLogEntry(actorUid: 'doc', action: 'patient.view', at: _before),
      ],
    );
    expect(s.of('front').checkedIn, 1);
    expect(s.of('front').lastActivity, _in);
    expect(s.of('doc').recordsOpened, 2);
    expect(s.of('doc').filesDownloaded, 1);
    expect(s.of('doc').lastActivity, later);
    expect(s.clinic.recordsOpened, 2);
  });

  test('records without a maker count for the clinic only', () {
    final s = TeamStats.compute(
      from: _from,
      to: _to,
      visits: [_visit(booker: '', doctor: '')],
    );
    expect(s.clinic.booked, 1);
    expect(s.clinic.attended, 1);
    expect(s.unattributed, 1);
    expect(s.byPerson, isEmpty);
    expect(s.of('anyone').isEmpty, isTrue);
  });
}
