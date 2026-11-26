import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Stroke icons for the physiotherapy workspace, drawn like [CruIcons]
/// (24-unit viewBox, round caps), so they match the rest of the app.
abstract final class PhysioIcons {
  /// Simple stroked standing figure.
  static const physio = CruIconData(
    'M12 7.5v7M6.5 10.5l5.5-1 5.5 1M9 21l3-6.5 3 6.5',
    circles: [(12, 5, 2.5)],
  );
}
