import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';

typedef _Placed = ({ToothChartEntryModel entry, int slot, DateTime time});

/// A patient's chart as a line of visits (sessions), like commits on one
/// git branch. A chart row belongs to the visit it was saved in
/// ([ToothChartEntryModel.visitId]); a row without one (older data, or
/// saved outside a visit) belongs to the last visit that had started when
/// it was recorded.
///
/// What a visit shows: for each tooth, the newest row from that visit or
/// an earlier one. So a change made in an earlier visit carries forward
/// to later visits, unless a later visit changed that tooth itself (a
/// collision: the later change wins from there on). Changes never travel
/// backwards.
class ChartTimeline {
  ChartTimeline._(this.sessions, this._index, this._placed);

  factory ChartTimeline(
    Iterable<Visit> visits,
    List<ToothChartEntryModel> entries, {
    required DateTime now,
  }) {
    final withRows = <String>{
      for (final e in entries)
        if (!e.isDeleted && e.visitId != null) e.visitId!,
    };
    final endOfToday = DateTime(now.year, now.month, now.day + 1);
    final sessions = <Visit>[
      for (final v in visits)
        if (!v.isDeleted &&
            (withRows.contains(v.id) ||
                (v.status != VisitStatus.cancelled &&
                    v.status != VisitStatus.missed &&
                    v.scheduledStart.isBefore(endOfToday))))
          v,
    ]..sort(_bySession);
    final index = <String, int>{
      for (var i = 0; i < sessions.length; i++) sessions[i].id: i,
    };

    // The last visit that had started at [t]; -1 before the first.
    int slotAt(DateTime t) {
      var slot = -1;
      for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].scheduledStart.isAfter(t)) break;
        slot = i;
      }
      return slot;
    }

    final placed = <_Placed>[];
    for (final e in entries) {
      if (e.isDeleted) continue;
      final own = e.visitId == null ? null : index[e.visitId];
      placed.add(
        own != null
            // In its visit: ordered by when it was written.
            ? (entry: e, slot: own, time: e.createdAt)
            // No (known) visit: by the date it was recorded for.
            : (entry: e, slot: slotAt(e.recordedAt), time: e.recordedAt),
      );
    }
    placed.sort((a, b) {
      final s = a.slot.compareTo(b.slot);
      if (s != 0) return s;
      final t = a.time.compareTo(b.time);
      if (t != 0) return t;
      return a.entry.id.compareTo(b.entry.id);
    });
    return ChartTimeline._(sessions, index, placed);
  }

  static int _bySession(Visit a, Visit b) {
    final s = a.scheduledStart.compareTo(b.scheduledStart);
    if (s != 0) return s;
    final c = a.createdAt.compareTo(b.createdAt);
    if (c != 0) return c;
    return a.id.compareTo(b.id);
  }

  /// The visits that are sessions, oldest first.
  final List<Visit> sessions;
  final Map<String, int> _index;

  /// Every live row, oldest first along the line.
  final List<_Placed> _placed;

  /// Whether [visitId] is a session that can be loaded.
  bool isSession(String? visitId) =>
      visitId != null && _index.containsKey(visitId);

  /// The session [visitId], or null.
  Visit? sessionOf(String? visitId) {
    final i = visitId == null ? null : _index[visitId];
    return i == null ? null : sessions[i];
  }

  /// Rows up to this position are visible; null (Latest) sees them all.
  int _limit(String? visitId) =>
      visitId == null ? sessions.length : (_index[visitId] ?? sessions.length);

  /// The rows [visitId] can see, oldest first (null: every row).
  List<ToothChartEntryModel> visibleAt(String? visitId) {
    final limit = _limit(visitId);
    return [
      for (final p in _placed)
        if (p.slot <= limit) p.entry,
    ];
  }

  /// Each tooth's row as [visitId] shows it (null: the latest chart).
  Map<String, ToothChartEntryModel> latestAt(String? visitId) {
    final map = <String, ToothChartEntryModel>{};
    for (final e in visibleAt(visitId)) {
      map[e.toothNumber] = e;
    }
    return map;
  }

  /// [visitId]'s own rows for [tooth] (what undo removes).
  List<ToothChartEntryModel> ownRows(String visitId, String tooth) => [
    for (final p in _placed)
      if (p.entry.visitId == visitId && p.entry.toothNumber == tooth) p.entry,
  ];

  /// Teeth [visitId] changed itself.
  Set<String> changedIn(String visitId) => {
    for (final p in _placed)
      if (p.entry.visitId == visitId) p.entry.toothNumber,
  };

  /// Later visits that changed [tooth] after [visitId], oldest first. An
  /// edit made in [visitId] carries forward only up to the first of them.
  List<Visit> laterChanges(String visitId, String tooth) {
    final i = _index[visitId];
    if (i == null) return const [];
    final slots = <int>{
      for (final p in _placed)
        if (p.slot > i && p.entry.toothNumber == tooth) p.slot,
    };
    return [
      for (final s in slots.toList()..sort())
        if (s >= 0 && s < sessions.length) sessions[s],
    ];
  }

  /// Teeth whose change in [visitId] was made on top of an older state:
  /// an earlier visit changed the tooth after (a conflict, as in git). The
  /// later change still wins; this only flags it. Saving the tooth again
  /// in [visitId] clears it.
  Set<String> conflictsIn(String visitId) {
    final i = _index[visitId];
    if (i == null) return const {};
    final before = <String, ToothChartEntryModel>{};
    final newestOwn = <String, ToothChartEntryModel>{};
    final beforeOwn = <String, ToothChartEntryModel?>{};
    for (final p in _placed) {
      if (p.slot > i) break;
      final e = p.entry;
      if (e.visitId == visitId) {
        newestOwn[e.toothNumber] = e;
        beforeOwn[e.toothNumber] = before[e.toothNumber];
      }
      before[e.toothNumber] = e;
    }
    return {
      for (final MapEntry(key: tooth, value: e) in newestOwn.entries)
        if (e.baseEntryId != null &&
            e.baseEntryId != (beforeOwn[tooth]?.id ?? ''))
          tooth,
    };
  }

  /// Where [visitId]'s view ends in time: when the next session starts
  /// (null for Latest or the last session). Records (perio, endo) from
  /// before this belong to that view.
  DateTime? cutoff(String? visitId) {
    final i = visitId == null ? null : _index[visitId];
    if (i == null || i + 1 >= sessions.length) return null;
    return sessions[i + 1].scheduledStart;
  }
}

