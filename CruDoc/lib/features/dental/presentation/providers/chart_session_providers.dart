import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/domain/chart_timeline.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';

/// The visit Charting has loaded as a session for a patient; null shows
/// the latest chart.
final chartSessionProvider = StateProvider.family<String?, String>(
  (ref, patientId) => null,
);

/// The patient's visits and chart rows as one line of sessions.
final chartTimelineProvider = Provider.family<ChartTimeline, String>((
  ref,
  patientId,
) {
  final visits =
      ref.watch(patientSummaryProvider(patientId)).value?.visits ??
      const <Visit>[];
  final entries =
      ref.watch(patientToothChartProvider(patientId)).value ??
      const <ToothChartEntryModel>[];
  return ChartTimeline(visits, entries, now: DateTime.now());
});

/// The loaded session for [patientId], if it is still one.
String? watchChartSession(WidgetRef ref, String patientId) {
  final id = ref.watch(chartSessionProvider(patientId));
  return ref.watch(chartTimelineProvider(patientId)).isSession(id) ? id : null;
}

/// The visit a new chart change for [patientId] is saved in: the loaded
/// session, else today's visit, else none (saved by its date).
Visit? chartWriteVisit(WidgetRef ref, String patientId) {
  final timeline = ref.read(chartTimelineProvider(patientId));
  final loaded = timeline.sessionOf(ref.read(chartSessionProvider(patientId)));
  if (loaded != null) return loaded;
  final visits = ref.read(patientSummaryProvider(patientId)).value?.visits;
  final now = DateTime.now();
  for (final v in visits ?? const <Visit>[]) {
    if (v.status == VisitStatus.cancelled) continue;
    if (DateUtils.isSameDay(v.scheduledStart, now)) return v;
  }
  return null;
}

/// What a new row on [tooth] saved in [visit] replaces ('' for nothing).
String chartBaseFor(WidgetRef ref, String patientId, Visit? visit, String tooth) =>
    ref.read(chartTimelineProvider(patientId)).latestAt(visit?.id)[tooth]?.id ??
    '';

