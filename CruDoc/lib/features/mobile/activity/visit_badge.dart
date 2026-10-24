import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A patient's avatar (Notifications, Today's schedule) with a small badge
/// at its bottom right, the way Instagram puts a heart on a profile photo:
/// blue with a calendar for an appointment, green with a house for a home
/// visit. A ring of the background's colour keeps it apart from the avatar.
class VisitBadged extends StatelessWidget {
  const VisitBadged({
    super.key,
    required this.avatar,
    required this.avatarSize,
    required this.homeVisit,
    this.ringColor,
  });

  final Widget avatar;
  final double avatarSize;
  final bool homeVisit;

  /// What's behind the avatar (the ring matches it); the card by default.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Readable, but never so big that it covers the initials.
    final badge = (avatarSize * 0.5).clamp(20.0, 22.0).roundToDouble();
    final ring = badge / 10;
    // Centred on the avatar's edge at its bottom right (45°), like
    // Instagram's heart, so it sits half outside the circle.
    final radius = avatarSize / 2;
    final out = badge / 2 - radius * (1 - math.sqrt1_2);
    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -out,
            bottom: -out,
            child: Container(
              width: badge,
              height: badge,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: homeVisit ? c.green : c.accent,
                shape: BoxShape.circle,
                border: Border.all(color: ringColor ?? c.surface, width: ring),
              ),
              child: CruIcon(
                homeVisit ? CruIcons.home : CruIcons.calendar,
                size: badge * 0.56,
                strokeWidth: 2.2,
                color: c.onAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
