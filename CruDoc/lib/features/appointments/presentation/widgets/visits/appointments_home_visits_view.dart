import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/visits/home_visit_links.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_context_region.dart';
import 'package:doctor_management_app/core/services/maps_key.dart';

/// Share of the width the stop list takes; the map takes the rest.
const int _kListFlex = 5;
const int _kMapFlex = 4;

/// The stop number beside each visit.
const double _kStopBadge = 28;

const double _kMapAspect = kHomeMapWidth / kHomeMapHeight;

/// Schedule, Home visits (physiotherapy): the anchor day's home visits in
/// time order on the left, the route on a map on the right. The desktop
/// counterpart of the phone's Visitations tab.
class AppointmentsHomeVisitsView extends ConsumerWidget {
  const AppointmentsHomeVisitsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final anchor = ref.watch(apptsControllerProvider.select((s) => s.anchor));
    final async = ref.watch(apptItemsProvider);
    final all = async.value;

    if (all == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: async.hasError
            ? CruCard(
                child: Text(
                  "Couldn't load visits.",
                  style: CruType.text.tint(c.label2),
                ),
              )
            : const SkeletonCard(rows: 4),
      );
    }

    final stops =
        ApptsBuilder.forDay(
            all,
            anchor,
          ).where((i) => i.visit.visitType == VisitType.home).toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    if (stops.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: CruCard(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s24,
            vertical: CruSpace.s32,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No home visits', style: CruType.headline.tint(c.label)),
                const SizedBox(height: CruSpace.s4),
                Text(
                  'Nothing booked at a patient’s home on '
                  '${DateFormat('d MMMM').format(anchor)}.',
                  textAlign: TextAlign.center,
                  style: CruType.text.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s16),
                // A Row so the capsule keeps its own width.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CruCapsuleButton(
                      label: 'Book a home visit',
                      icon: CruIcons.plus,
                      onPressed: () => ApptActions.newAppointment(
                        context,
                        ref,
                        day: anchor,
                        type: VisitType.home,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: _kListFlex,
          child: SingleChildScrollView(child: _StopList(stops: stops)),
        ),
        const SizedBox(width: CruSpace.cardGap),
        Expanded(
          flex: _kMapFlex,
          child: _RouteCard(stops: stops),
        ),
      ],
    );
  }
}

class _StopList extends StatelessWidget {
  const _StopList({required this.stops});

  final List<ApptItem> stops;

  @override
  Widget build(BuildContext context) {
    return CruCard(
      semanticLabel: 'Home visits',
      padding: const EdgeInsets.all(CruSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stops.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: CruSpace.s4),
                child: CruSeparator(
                  indent: CruSpace.s12 + _kStopBadge + CruSpace.s12,
                ),
              ),
            _StopRow(number: i + 1, item: stops[i]),
          ],
        ],
      ),
    );
  }
}

class _StopRow extends ConsumerWidget {
  const _StopRow({required this.number, required this.item});

  final int number;
  final ApptItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final v = item.visit;
    final done = item.status == ApptStatus.done;
    final missed = item.status == ApptStatus.missed;
    final address = v.address.trim();
    final directions = homeVisitDirections(v);

    return ApptContextRegion(
      item: item,
      child: CruPressable(
        onTap: () => ApptActions.openVisit(context, item),
        semanticLabel: 'Stop $number, ${item.name}',
        scaleOnPress: false,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          padding: const EdgeInsets.all(CruSpace.s12),
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _kStopBadge,
                height: _kStopBadge,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? c.greenTint : (missed ? c.inset : c.barActive),
                ),
                child: done
                    ? CruIcon(
                        CruIcons.check,
                        size: 14,
                        strokeWidth: 2.4,
                        color: c.greenText,
                      )
                    : Text(
                        '$number',
                        style: CruType.caption.w600.tabular.tint(
                          missed ? c.label3 : c.onAccent,
                        ),
                      ),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          DashFormat.timeRange(item.start, item.end),
                          style: CruType.caption.w600.tabular.tint(c.label2),
                        ),
                        if (done || missed) ...[
                          const SizedBox(width: CruSpace.s8),
                          Text(
                            done ? 'Done' : 'Missed',
                            style: CruType.caption.w600.tint(
                              done ? c.greenText : c.label3,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      [item.name, ?item.reason].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.callout.tint(missed ? c.label3 : c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      address.isEmpty ? 'No address saved' : address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.caption.tint(
                        address.isEmpty ? c.label3 : c.label2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s12),
              if (directions != null)
                CruCapsuleButton(
                  label: 'Directions',
                  icon: CruIcons.arrowUpRight,
                  onPressed: () => openHomeVisitLink(directions),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteCard extends ConsumerWidget {
  const _RouteCard({required this.stops});

  final List<ApptItem> stops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    ref.watch(mapsKeyProvider); // draws the map once the key arrives
    final route = homeVisitRoute(stops);
    final mapUrl = homeVisitMapUrl(stops);
    final pinned = stops
        .where((s) => s.visit.latitude != null && s.visit.longitude != null)
        .length;

    return CruCard(
      semanticLabel: 'Route',
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Route', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s2),
          Text(
            pinned == stops.length
                ? 'Stops in visit order'
                : '$pinned of ${stops.length} stops on the map · pick the '
                      'address from the suggestions to pin the rest',
            style: CruType.caption.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s16),
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(CruRadius.control),
            child: AspectRatio(
              aspectRatio: _kMapAspect,
              child: mapUrl == null
                  ? ColoredBox(
                      color: c.inset,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(CruSpace.s16),
                          child: Text(
                            pinned == 0
                                ? 'No stop has a pinned address yet.'
                                : 'Map preview isn’t available on this computer.',
                            textAlign: TextAlign.center,
                            style: CruType.caption.tint(c.label2),
                          ),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: mapUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => ColoredBox(color: c.inset),
                      errorWidget: (_, _, _) => ColoredBox(
                        color: c.inset,
                        child: Center(
                          child: Text(
                            'Couldn’t load the map.',
                            style: CruType.caption.tint(c.label2),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (route != null) ...[
            const SizedBox(height: CruSpace.s16),
            CruButton(
              label: stops.length > 1
                  ? 'Open route in Google Maps'
                  : 'Open in Google Maps',
              kind: CruButtonKind.secondary,
              icon: CruIcons.arrowUpRight,
              expand: true,
              onPressed: () => openHomeVisitLink(route),
            ),
          ],
        ],
      ),
    );
  }
}
