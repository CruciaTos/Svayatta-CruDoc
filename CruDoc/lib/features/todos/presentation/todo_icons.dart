import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons for the To-do page (24-unit stroke paths, like CruIcons).
abstract final class TodoIcons {
  /// A ticked box: the page's own icon.
  static const check = CruIconData(
    'M9 11.5l2.5 2.5L16 9.5',
    rects: [(4, 4, 16, 16, 4)],
  );

  /// A push pin.
  static const pin = CruIconData('M8 3h8M9.5 3v6.5L6 14h12l-3.5-4.5V3M12 14v7');

  /// The same pin, filled (pinned).
  static const pinFilled = CruIconData(
    'M8 3h8v1.5h-1.5v5L18 14H6l3.5-4.5v-5H8ZM11.25 14h1.5v7h-1.5Z',
    filled: true,
  );

  /// Circular arrows: repeats.
  static const repeat = CruIconData(
    'M17 2l3 3-3 3M4 11V9a4 4 0 0 1 4-4h12M7 22l-3-3 3-3M20 13v2a4 4 0 0 1-4 4H4',
  );
}
