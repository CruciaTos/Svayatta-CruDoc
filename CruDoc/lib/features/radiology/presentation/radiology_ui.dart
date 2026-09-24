import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Radiology stroke icons in the Calm Clinical style (24-unit viewBox).
abstract final class RadIcons {
  /// Worklist: rows with a box each.
  static const worklist = CruIconData(
    'M10 6.5h10M10 12h10M10 17.5h10',
    rects: [(3.5, 5, 3, 3, 0.8), (3.5, 10.5, 3, 3, 0.8), (3.5, 16, 3, 3, 0.8)],
  );

  /// Report: a page with lines.
  static const report = CruIconData(
    'M14 3.5H7.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V8zM14 3.5V8h4.5'
    'M9 12.5h6M9 16h6',
  );

  /// Referrer: a person with an arrow.
  static const referrer = CruIconData(
    'M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM3.5 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5'
    'M16 8.5h5M19 6l2.5 2.5L19 11',
  );

  /// CBCT / 3D: a cube.
  static const cube = CruIconData(
    'M12 3 20 7.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9',
  );

  /// 2D X-ray: a film with the arches.
  static const xray = CruIconData(
    'M3.5 7.5a2 2 0 0 1 2-2h13a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z'
    'M7 10.5c1.5 1 3 1.5 5 1.5s3.5-.5 5-1.5M7 14c1.5-.8 3-1.2 5-1.2s3.5.4 5 1.2',
  );

  /// Import: into a tray.
  static const import = CruIconData(
    'M12 4v10M8 10l4 4 4-4M4.5 15v3a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-3',
  );

  static const folder = CruIconData(
    'M3.5 7a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z',
  );

  /// PACS / DICOM server.
  static const server = CruIconData(
    'M7.5 7.25h.01M7.5 16.75h.01',
    rects: [(4, 4, 16, 6.5, 2), (4, 13.5, 16, 6.5, 2)],
  );

  static const cloud = CruIconData(
    'M7 18.5a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.5 1.3A3.9 3.9 0 0 1 17.5 18.5z',
  );

  static const print = CruIconData(
    'M7 9V4h10v5M7 17H5.5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h13a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H17'
    'M7 14h10v6H7z',
  );

  static const mail = CruIconData('M4 6.5h16v11H4zM4 7l8 6 8-6');

  /// Radiation (dose log).
  static const dose = CruIconData(
    'M9.2 7.2 6.5 2.8A10 10 0 0 0 2 11h5.2a4.8 4.8 0 0 1 2-3.8z'
    'M14.8 7.2l2.7-4.4A10 10 0 0 1 22 11h-5.2a4.8 4.8 0 0 0-2-3.8z'
    'M9.4 16.2 6.7 20.6a10 10 0 0 0 10.6 0l-2.7-4.4a4.8 4.8 0 0 1-5.2 0z',
    circles: [(12, 12, 1.6)],
  );

  /// Audit log: history.
  static const history = CruIconData(
    'M4.5 12a7.5 7.5 0 1 0 2.2-5.3M4.5 4.5v4h4M12 8v4.5l3 2',
  );

  static const template = CruIconData(
    'M4.5 4.5h15v4h-15zM4.5 11.5h6.5v8H4.5zM14 11.5h5.5M14 15.5h5.5M14 19.5h5.5',
  );

  /// Phrase library: text that expands.
  static const phrase = CruIconData('M4 7h16M4 12h10M4 17h7M16 14.5l3 2.5-3 2.5');

  static const eye = CruIconData(
    'M2.5 12s3.5-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.5 6.5-9.5 6.5S2.5 12 2.5 12z',
    circles: [(12, 12, 3)],
  );

  /// Open next unread.
  static const next = CruIconData('M6 6l6 6-6 6M13 6l6 6-6 6');

  static const trash = CruIconData(
    'M4.5 6.5h15M9.5 6.5V4.5h5v2M6.5 6.5l1 13h9l1-13',
  );

  /// Not connected: a broken link.
  static const unlink = CruIconData(
    'M9.5 14.5l-2 2a3 3 0 0 1-4.2-4.2l2-2M14.5 9.5l2-2a3 3 0 0 1 4.2 4.2l-2 2'
    'M4 4l16 16',
  );

  static const flag = CruIconData('M5.5 20.5v-16M5.5 4.5h11l-2 4 2 4h-11');
  static const signature = CruIconData(
    'M3.5 17c2.5 0 3.5-9 5.5-9s1 7 3 7 2-3 3.5-3 1 2.5 2.5 2.5M3.5 20.5h17',
  );
  static const share = CruIconData(
    'M12 3.5v11M8 7.5l4-4 4 4M5.5 12v6.5a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V12',
  );
}

/// Dates, turnaround and sizes on the radiology screens.
abstract final class RadFormat {
  static String date(DateTime d) => DateFormat('d MMM yyyy').format(d);
  static String shortDate(DateTime d) => DateFormat('d MMM').format(d);
  static String time(DateTime d) => DateFormat('h:mm a').format(d);
  static String dateTime(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);

  /// "5 min ago", "3h ago", "Yesterday", "12 Sep".
  static String ago(DateTime d, DateTime now) {
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return shortDate(d);
  }

  static String _span(Duration d) {
    final h = d.inHours;
    if (h >= 48) return '${(h / 24).round()} days';
    if (h >= 1) return '${h}h';
    return '${d.inMinutes.clamp(1, 59)} min';
  }

  /// Turnaround text and whether it's late or close: "Due in 5h",
  /// "Overdue 2h", "Signed".
  static ({String text, bool late, bool soon}) due(RadStudy s, DateTime now) {
    if (!s.status.isOpen) return (text: s.status.label, late: false, soon: false);
    final due = s.dueAt;
    if (due == null) return (text: 'No due time', late: false, soon: false);
    if (now.isAfter(due)) {
      return (text: 'Overdue ${_span(now.difference(due))}', late: true, soon: false);
    }
    final left = due.difference(now);
    return (text: 'Due in ${_span(left)}', late: false, soon: left.inHours < 4);
  }

  /// "34 y · Female".
  static String patientLine(RadStudy s, DateTime now) {
    final parts = <String>[];
    final dob = s.patientDob;
    if (dob != null) {
      var y = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) y--;
      parts.add('$y y');
    }
    if (s.patientSex.isNotEmpty) parts.add(s.patientSex);
    return parts.join(' · ');
  }

  static String bytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static String rupees(double v) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);

  /// "1 image", "320 images".
  static String images(int n) => n == 1 ? '1 image' : '$n images';
}

/// New (teal), Reading (amber: waiting on you), Draft/Preliminary (grey),
/// Final and Sent (green: done).
Widget radStatusPill(CruColors c, RadStudyStatus s) => switch (s) {
      RadStudyStatus.newStudy =>
        CruPill(text: 'New', background: c.tealTint, foreground: c.tealText),
      RadStudyStatus.reading =>
        CruPill(text: 'Reading', background: c.amberTint, foreground: c.amberText),
      RadStudyStatus.draft =>
        CruPill(text: 'Draft', background: c.inset, foreground: c.label2),
      RadStudyStatus.preliminary =>
        CruPill(text: 'Preliminary', background: c.inset, foreground: c.label),
      RadStudyStatus.finalised =>
        CruPill(text: 'Final', background: c.greenTint, foreground: c.greenText),
      RadStudyStatus.delivered =>
        CruPill(text: 'Sent', background: c.greenTint, foreground: c.greenText),
    };

/// Routine shows nothing; Urgent amber; STAT red (a patient-safety
/// matter: the referrer needs it now).
Widget? radPriorityPill(CruColors c, RadPriority p) => switch (p) {
      RadPriority.routine => null,
      RadPriority.urgent =>
        CruPill(text: 'Urgent', background: c.amberTint, foreground: c.amberText),
      RadPriority.stat => CruPill(text: 'STAT', background: c.redTint, foreground: c.redText),
    };

Widget radReportStatusPill(CruColors c, RadReportStatus s) => switch (s) {
      RadReportStatus.draft =>
        CruPill(text: 'Draft', background: c.inset, foreground: c.label2),
      RadReportStatus.preliminary =>
        CruPill(text: 'Preliminary', background: c.amberTint, foreground: c.amberText),
      RadReportStatus.finalised =>
        CruPill(text: 'Final', background: c.greenTint, foreground: c.greenText),
    };

/// The study type as a small badge: "CBCT", "OPG".
class RadModalityBadge extends StatelessWidget {
  const RadModalityBadge(this.modality, {super.key, this.width = 58});

  final RadModality modality;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final volume = modality.isVolume;
    return Container(
      width: width,
      height: CruSize.pill,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: volume ? c.tealTint : c.inset,
        shape: const StadiumBorder(),
      ),
      child: Text(
        modality.short,
        maxLines: 1,
        style: CruType.caption.w600.tint(volume ? c.tealText : c.label2),
      ),
    );
  }
}

/// Says plainly that a feature is built but not connected yet (PACS,
/// cloud links, AI), and what connecting it will do.
class RadNotConnected extends StatelessWidget {
  const RadNotConnected({
    super.key,
    required this.title,
    required this.body,
    this.icon = RadIcons.unlink,
    this.compact = false,
  });

  final String title;
  final String body;
  final CruIconData icon;

  /// One line with the title only (for toolbars and panels).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CruIcon(icon, size: 14, strokeWidth: 2, color: c.label3),
          const SizedBox(width: CruSpace.s6),
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.caption.w500.tint(c.label2)),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CruIcon(icon, size: 18, strokeWidth: 1.8, color: c.label2),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.subhead.w600.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(body, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short message at the bottom of the window.
void radToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      width: 420,
      duration: const Duration(seconds: 3),
    ));
}
