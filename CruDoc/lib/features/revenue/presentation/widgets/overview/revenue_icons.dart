import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons the Revenue design uses that `CruIcons` doesn't have yet
/// (requested in design/clinic-redesign/NEEDS.md, Builder 4). Paths are
/// copied from html/Revenue.dc.html.
abstract final class RevenueIcons {
  /// Receipt: "Record expense" and money-out rows.
  static const CruIconData receipt =
      CruIconData('M6 3.5h12v17l-3-2-3 2-3-2-3 2z M9 8.5h6M9 12.5h6');

  /// Chat bubble: "Send reminders on WhatsApp".
  static const CruIconData chat = CruIconData(
    'M20.5 11.5a8.5 8.5 0 0 1-12.4 7.5L3.5 20.5l1.4-4.3A8.5 8.5 0 1 1 20.5 11.5z',
  );
}
