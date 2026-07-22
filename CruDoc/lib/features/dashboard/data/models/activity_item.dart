import 'package:flutter/material.dart';

/// A single row in the dashboard's "Recent Activity" feed — a patient,
/// visit, inventory, or revenue event flattened down to what the card
/// needs to render.
class ActivityItem {
  final IconData icon;
  final String text;

  /// When this event actually happened (not when it was fetched) —
  /// e.g. a patient's `createdAt`, a visit's `updatedAt` (the moment its
  /// current status took effect), a stock transaction's `createdAt`, or
  /// a revenue entry's `createdAt`. Used both to sort the merged feed
  /// and to render [relativeTime].
  final DateTime timestamp;

  const ActivityItem({
    required this.icon,
    required this.text,
    required this.timestamp,
  });

  /// Human-readable relative time (e.g. "2 hours ago", "Just now"),
  /// matching the convention already used across the patients feature —
  /// see `_formatRelativeTime` in patient_details.dart, patient_records.dart,
  /// and last_patient.dart.
  String get relativeTime => _formatRelativeTime(timestamp);
}

String _formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    final mins = difference.inMinutes;
    return '$mins ${mins == 1 ? 'minute' : 'minutes'} ago';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  } else if (difference.inDays < 30) {
    final days = difference.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  } else if (difference.inDays < 365) {
    final months = (difference.inDays / 30).floor();
    return '$months ${months == 1 ? 'month' : 'months'} ago';
  } else {
    final years = (difference.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }
}
