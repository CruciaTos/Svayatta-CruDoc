import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';

/// The sessions a file taken now could belong to: the patient's visits up
/// to today, newest first.
List<Visit> sessionChoices(Iterable<Visit> visits, DateTime now) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  return visits
      .where(
        (v) =>
            !v.isDeleted &&
            v.status != VisitStatus.cancelled &&
            v.scheduledStart.isBefore(tomorrow),
      )
      .toList()
    ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
}

/// "Today · 10:30 AM · Cleaning".
String sessionLabel(Visit v, DateTime now) {
  final t = v.scheduledStart;
  final reason = v.treatmentType?.trim() ?? '';
  return [
    DateUtils.isSameDay(t, now)
        ? 'Today'
        : DateFormat(t.year == now.year ? 'EEE d MMM' : 'd MMM y').format(t),
    DateFormat('h:mm a').format(t),
    if (reason.isNotEmpty) reason,
  ].join(' · ');
}
