import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_top_bar.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/poster_hero.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Phone Patient details' pinned top: the way back, the patient's mini
/// identity (monogram, name; red ring when allergic) and the ••• menu.
/// The identity fades in as the poster's name scrolls under the bar
/// ([identity], 0 to 1), or stays shown while [identityShown] (the
/// Clinical page, an open sub-screen). Nothing else lives here.
class PatientPinnedBar extends StatelessWidget {
  const PatientPinnedBar({
    super.key,
    required this.summary,
    required this.allergic,
    required this.onBack,
    required this.menu,
    required this.identity,
    this.backLabel,
    this.identityShown = false,
  });

  final PatientSummary summary;
  final bool allergic;
  final VoidCallback onBack;

  /// The back link's label while a sub-screen is open ("Overview").
  final String? backLabel;

  /// The ••• menu.
  final Widget menu;

  /// How much of the mini identity shows, 0 to 1, from the page's scroll.
  final ValueListenable<double> identity;

  /// Forces the mini identity on (200 ms fade) whatever [identity] says.
  final bool identityShown;

  /// Height of the bar.
  static const double height = CruSize.control + CruSpace.s8;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = summary.patient;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
        child: Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: DetailsBackLink(onBack: onBack, label: backLabel),
                ),
              ),
            ),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: identityShown ? 1 : 0),
                duration: CruMotion.of(context, CruMotion.fast),
                curve: CruMotion.curve,
                builder: (context, forced, _) => ValueListenableBuilder<double>(
                  valueListenable: identity,
                  builder: (context, scrolled, _) {
                    final opacity = math.max(forced, scrolled).clamp(0.0, 1.0);
                    return IgnorePointer(
                      child: ExcludeSemantics(
                        excluding: opacity == 0,
                        child: Opacity(
                          opacity: opacity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CruSpace.s8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                PatientAvatar(
                                  name: p.fullName,
                                  size: 28,
                                  allergic: allergic,
                                ),
                                const SizedBox(width: CruSpace.s8),
                                Flexible(
                                  child: Text(
                                    p.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MobileType.title2.tint(c.label),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            menu,
          ],
        ),
      ),
    );
  }
}
