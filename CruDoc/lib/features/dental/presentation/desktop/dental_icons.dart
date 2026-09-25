import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Dental stroke icons in the Calm Clinical style (24-unit viewBox).
abstract final class DentalIcons {
  static const tooth = CruIconData(
    'M7 3.5C4.8 3.5 3.5 5.3 3.5 7.7C3.5 10 4.4 11.6 5.1 13.3'
    'C5.7 14.8 5.9 16.6 6.2 18.3C6.4 19.7 7 20.5 7.8 20.5'
    'C8.8 20.5 9.2 19.6 9.5 18.1L10.1 15C10.3 14 11 13.4 12 13.4'
    'C13 13.4 13.7 14 13.9 15L14.5 18.1C14.8 19.6 15.2 20.5 16.2 20.5'
    'C17 20.5 17.6 19.7 17.8 18.3C18.1 16.6 18.3 14.8 18.9 13.3'
    'C19.6 11.6 20.5 10 20.5 7.7C20.5 5.3 19.2 3.5 17 3.5'
    'C15.4 3.5 14.1 4.4 12 4.4C9.9 4.4 8.6 3.5 7 3.5Z',
  );

  /// Sterilization: a shield with a tick.
  static const shield = CruIconData(
    'M12 3 4.5 6v5.5c0 4.6 3.1 8.2 7.5 9.5 4.4-1.3 7.5-4.9 7.5-9.5V6z'
    'M9 12l2 2 4-4',
  );

  /// Treatment plans: a clipboard.
  static const plan = CruIconData(
    'M9 4.5H7.5A2.5 2.5 0 0 0 5 7v11.5A2.5 2.5 0 0 0 7.5 21h9'
    'a2.5 2.5 0 0 0 2.5-2.5V7a2.5 2.5 0 0 0-2.5-2.5H15M9 11.5h6M9 15.5h4',
    rects: [(9, 3, 6, 3, 1.5)],
  );

  /// Back to the starting view.
  static const reset = CruIconData('M4.5 12a7.5 7.5 0 1 0 2.2-5.3M4.5 4.5v4h4');

  /// Procedures: a list.
  static const procedures = CruIconData(
    'M9.5 6.5h10M9.5 12h10M9.5 17.5h10',
    circles: [(5, 6.5, 1), (5, 12, 1), (5, 17.5, 1)],
  );
}
