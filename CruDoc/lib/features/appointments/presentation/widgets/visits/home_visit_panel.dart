import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/visits/home_visit_links.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/core/services/maps_key.dart';

/// A one-stop map is wider than the route map: 2 : 1.
const double _kMapAspect = 2;

/// Where a home visit happens, inside the Day view's selected card: the
/// address, a map of the spot (when it was pinned from the suggestions)
/// and Directions.
class HomeVisitPanel extends ConsumerWidget {
  const HomeVisitPanel({super.key, required this.item});

  final ApptItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    ref.watch(mapsKeyProvider); // draws the map once the key arrives
    final address = item.homeAddress;
    final map = homeVisitMapUrl([item]);
    final directions = homeVisitDirections(item.visit);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CruSpace.s12),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: CruSpace.s2),
                child: CruIcon(
                  CruIcons.home,
                  size: 16,
                  strokeWidth: 2.2,
                  color: c.homeVisit,
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              Expanded(
                child: Text(
                  address ?? 'No address saved',
                  style: CruType.subhead.tint(
                    address == null ? c.label3 : c.label,
                  ),
                ),
              ),
            ],
          ),
          if (map != null) ...[
            const SizedBox(height: CruSpace.s12),
            ClipRSuperellipse(
              borderRadius: BorderRadius.circular(CruRadius.bar),
              child: AspectRatio(
                aspectRatio: _kMapAspect,
                child: CachedNetworkImage(
                  imageUrl: map,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => ColoredBox(color: c.track),
                  errorWidget: (_, _, _) => ColoredBox(color: c.track),
                ),
              ),
            ),
          ],
          if (directions != null) ...[
            const SizedBox(height: CruSpace.s12),
            // A Row so the capsule keeps its own width.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CruCapsuleButton(
                  label: 'Directions',
                  icon: CruIcons.arrowUpRight,
                  kind: CruCapsuleKind.surface,
                  onPressed: () => openHomeVisitLink(directions),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
