import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/chart_timeline.dart';

final _now = DateTime(2026, 10, 31, 12);

Visit _visit(
  String id,
  DateTime start, {
  VisitStatus status = VisitStatus.completed,
}) => Visit(
  id: id,
  patientId: 'p',
  scheduledStart: start,
  durationMinutes: 30,
  address: '',
  status: status,
  createdAt: start,
  updatedAt: start,
);

ToothChartEntryModel _row(
  String id,
  String tooth,
  String condition, {
  String? visitId,
  String? base,
  required DateTime at,
  bool deleted = false,
}) => ToothChartEntryModel(
  id: id,
  doctorId: 'd',
  patientId: 'p',
  toothNumber: tooth,
  condition: condition,
  visitId: visitId,
  baseEntryId: base,
  recordedAt: at,
  createdAt: at,
  updatedAt: at,
  isDeleted: deleted,
);

void main() {
  final d1 = DateTime(2026, 10, 1, 10);
  final d2 = DateTime(2026, 10, 10, 10);
  final d3 = DateTime(2026, 10, 20, 10);
  final visits = [_visit('v1', d1), _visit('v2', d2), _visit('v3', d3)];

  test('an earlier change carries forward, never backwards', () {
    final t = ChartTimeline(visits, [
      _row('a', '16', 'decay', visitId: 'v2', base: '', at: d2),
    ], now: _now);

    expect(t.latestAt('v1')['16'], isNull);
    expect(t.latestAt('v2')['16']?.condition, 'decay');
    expect(t.latestAt('v3')['16']?.condition, 'decay');
    expect(t.latestAt(null)['16']?.condition, 'decay');
  });

  test('a later visit changing the same tooth wins from there on', () {
    final t = ChartTimeline(visits, [
      _row('a', '16', 'decay', visitId: 'v1', base: '', at: d1),
      _row('b', '16', 'restored', visitId: 'v2', base: 'a', at: d2),
      // Edited back in v1 after v2 was charted.
      _row('c', '16', 'fractured', visitId: 'v1', base: 'a', at: d3),
    ], now: _now);

    expect(t.latestAt('v1')['16']?.id, 'c');
    expect(t.latestAt('v2')['16']?.id, 'b');
    expect(t.latestAt('v3')['16']?.id, 'b');
    expect(t.laterChanges('v1', '16').map((v) => v.id), ['v2']);
    expect(t.changedIn('v1'), {'16'});
  });

  test('a change made on top of an older state is flagged', () {
    final t = ChartTimeline(visits, [
      _row('a', '16', 'decay', visitId: 'v1', base: '', at: d1),
      _row('b', '16', 'restored', visitId: 'v2', base: 'a', at: d2),
      // v1 changes the tooth again, so v2's row was made on top of 'a'.
      _row('c', '16', 'fractured', visitId: 'v1', base: 'a', at: d3),
    ], now: _now);

    expect(t.conflictsIn('v2'), {'16'});
    expect(t.conflictsIn('v1'), isEmpty);
  });

  test('saving the tooth again in the flagged visit clears the flag', () {
    final rows = [
      _row('a', '16', 'decay', visitId: 'v1', base: '', at: d1),
      _row('b', '16', 'restored', visitId: 'v2', base: 'a', at: d2),
      _row('c', '16', 'fractured', visitId: 'v1', base: 'a', at: d3),
    ];
    // The app saves a new row on top of what the visit shows (chartBaseFor).
    final base = ChartTimeline(visits, rows, now: _now).latestAt('v2')['16']!.id;
    final t = ChartTimeline(visits, [
      ...rows,
      _row(
        'd',
        '16',
        'restored',
        visitId: 'v2',
        base: base,
        at: d3.add(const Duration(hours: 1)),
      ),
    ], now: _now);

    expect(t.conflictsIn('v2'), isEmpty);
  });

  test('rows without a visit go to the last visit started by then', () {
    final t = ChartTimeline(visits, [
      _row('old', '11', 'missing', at: DateTime(2026, 9, 1)),
      _row('mid', '21', 'decay', at: DateTime(2026, 10, 15)),
    ], now: _now);

    expect(t.latestAt('v1').keys, ['11']);
    expect(t.latestAt('v2').keys, unorderedEquals(['11', '21']));
  });

  test('future, cancelled and missed visits without rows are not sessions', () {
    final t = ChartTimeline([
      ...visits,
      _visit('future', DateTime(2026, 11, 5)),
      _visit('cancelled', DateTime(2026, 10, 25), status: VisitStatus.cancelled),
      _visit('missed', DateTime(2026, 10, 26), status: VisitStatus.missed),
      _visit(
        'later today',
        DateTime(2026, 10, 31, 18),
        status: VisitStatus.scheduled,
      ),
    ], const [], now: _now);

    expect(t.sessions.map((v) => v.id), ['v1', 'v2', 'v3', 'later today']);
    expect(t.isSession('future'), isFalse);
    expect(t.isSession('cancelled'), isFalse);
  });

  test('a cancelled visit that holds chart rows stays a session', () {
    final t = ChartTimeline([
      ...visits,
      _visit('c', DateTime(2026, 10, 25), status: VisitStatus.cancelled),
    ], [
      _row('x', '36', 'decay', visitId: 'c', base: '', at: DateTime(2026, 10, 25)),
    ], now: _now);

    expect(t.isSession('c'), isTrue);
  });

  test('deleted rows are ignored', () {
    final t = ChartTimeline(visits, [
      _row('a', '16', 'decay', visitId: 'v1', base: '', at: d1, deleted: true),
    ], now: _now);

    expect(t.latestAt(null), isEmpty);
    expect(t.changedIn('v1'), isEmpty);
  });

  test('a view ends when the next session starts', () {
    final t = ChartTimeline(visits, const [], now: _now);

    expect(t.cutoff('v1'), d2);
    expect(t.cutoff('v3'), isNull);
    expect(t.cutoff(null), isNull);
  });
}
