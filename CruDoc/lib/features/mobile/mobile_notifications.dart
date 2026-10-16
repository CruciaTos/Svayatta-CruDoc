import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A bell, for Notifications. CruIcons has none yet; same stroke style
/// (24-unit viewBox, round caps).
const mobileBellIcon = CruIconData(
  'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0',
);

/// Opens Notifications over Home, the way Instagram's heart opens
/// Activity.
void openMobileNotifications(BuildContext context) => pushMobile(
  context,
  const MobileHostPage(backLabel: 'Home', child: MobileNotificationsScreen()),
);

/// What needs the doctor's attention, on its own page. Nothing feeds it
/// yet, so it is just its title: no stand-in items.
class MobileNotificationsScreen extends StatelessWidget {
  const MobileNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(
        bottom: MobileMetrics.navBottom(context) + CruSpace.s24,
      ),
      children: const [MobileHeader(pushed: true, title: 'Notifications')],
    );
  }
}
