import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/errors/visit_exceptions.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/appointment_actions.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/day/overlap_visit_row.dart';
import 'package:doctor_management_app/features/appointments/presentation/widgets/shell/appt_format.dart';
import 'package:doctor_management_app/features/messaging/data/providers/whatsapp_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';

/// Replaces the appointment card when an unsorted overlap is selected:
/// who overlaps, and a suggestion to move the most recently booked visit
/// to the next free slot. "Keep both" is a GAP (nothing stores that
/// decision), so it and its caption are hidden.
class OverlapCard extends ConsumerStatefulWidget {
  const OverlapCard({
    super.key,
    required this.group,
    required this.dayItems,
    required this.day,
  });

  final OverlapGroup group;
  final List<ApptItem> dayItems;

  /// Date only.
  final DateTime day;

  @override
  ConsumerState<OverlapCard> createState() => _OverlapCardState();
}

class _OverlapCardState extends ConsumerState<OverlapCard> {
  bool _sendWhatsApp = true;
  bool _moving = false;

  /// The visit to move and where, or null when no slot is free.
  (ApptItem, DateTime)? _suggestion(DateTime now) {
    final g = widget.group;
    final latest = ApptsBuilder.latestBooked(g);
    var after = latest.start;
    if (after.isBefore(now)) {
      final s = ApptsBuilder.snap(now);
      after = s.isBefore(now) ? s.add(const Duration(minutes: kApptSnapMinutes)) : s;
    }
    final slot = ApptsBuilder.nextFreeSlot(
      dayItems: widget.dayItems,
      after: after,
      durationMinutes: latest.durationMinutes,
      rangeEnd: ApptsBuilder.range(widget.dayItems, widget.day).end,
      excludeVisitId: latest.id,
    );
    return slot == null ? null : (latest, slot);
  }

  Future<void> _move(ApptItem item, DateTime slot) async {
    if (_moving) return;
    setState(() => _moving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = ref.read(visitRepositoryProvider);
    final whatsapp = ref.read(whatsappRepositoryProvider);
    final controller = ref.read(apptsControllerProvider.notifier);
    final from = item.start;
    final send = _sendWhatsApp;
    try {
      await repo.rescheduleVisit(item.id, newStart: slot);
    } on VisitException catch (e) {
      if (mounted) setState(() => _moving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            e is VisitOverlapWarning
                ? '${ApptFormat.time(slot)} is no longer free. Choose another time.'
                : e.message,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (_) {
      if (mounted) setState(() => _moving = false);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't move the visit. Try again."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    controller.select(item.id);
    if (send) {
      final moved = item.visit.copyWith(scheduledStart: slot);
      try {
        await whatsapp.sendAppointmentConfirmation(visit: moved);
      } catch (_) {
        // The move stands; the message is best effort.
      }
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Moved ${item.name} to ${ApptFormat.time(slot)}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await repo.rescheduleVisit(
                item.id,
                newStart: from,
                acknowledgeOverlap: true,
              );
            } catch (_) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text("Couldn't undo the move."),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final g = widget.group;
    final now = ref.watch(apptsNowProvider);
    final suggestion = _suggestion(now);
    final latest = ApptsBuilder.latestBooked(g);
    final hasPhone = (latest.patient?.phone.trim() ?? '').isNotEmpty;

    return CruCard(
      semanticLabel: 'Overlap at ${ApptFormat.time(g.peakStart)}',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s22,
        CruSpace.s20,
        CruSpace.s22,
        CruSpace.s18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CruPill(
                text: '${g.peak} visits at ${ApptFormat.time(g.peakStart)}',
                background: c.amberTint,
                foreground: c.amberText,
                icon: CruIcons.warning,
              ),
              const Spacer(),
              Text(
                ApptFormat.range(g.start, g.end),
                style: CruType.subhead.tabular.tint(c.label2),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          for (var i = 0; i < g.items.length; i++) ...[
            if (i > 0) const CruSeparator(indent: CruSize.monogramList + CruSpace.s12),
            OverlapVisitRow(item: g.items[i], now: now),
          ],
          if (suggestion != null) ...[
            const SizedBox(height: CruSpace.s10),
            _SuggestionBox(
              item: suggestion.$1,
              slot: suggestion.$2,
              showWhatsApp: hasPhone,
              sendWhatsApp: _sendWhatsApp,
              onWhatsApp: (v) => setState(() => _sendWhatsApp = v),
            ),
          ],
          const SizedBox(height: CruSpace.s14),
          Row(
            children: [
              if (suggestion != null)
                CruButton(
                  label: 'Move to ${ApptFormat.time(suggestion.$2)}',
                  onPressed: _moving
                      ? null
                      : () => _move(suggestion.$1, suggestion.$2),
                ),
              const Spacer(),
              CruLink(
                label: 'Other time',
                onPressed: () => ApptActions.reschedule(
                  context,
                  ref,
                  suggestion?.$1 ?? latest,
                ),
              ),
            ],
          ),
          // Seen together (a couple, a family)? One appointment, not a clash.
          if (g.items.fold<int>(0, (n, i) => n + i.patientCount) <=
              kMaxGroupPatients) ...[
            const SizedBox(height: CruSpace.s10),
            CruButton(
              label: 'Seen together? Combine into one',
              kind: CruButtonKind.inset,
              icon: CruIcons.patients,
              expand: true,
              onPressed: () => ApptActions.combine(context, ref, g.items),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionBox extends StatelessWidget {
  const _SuggestionBox({
    required this.item,
    required this.slot,
    required this.showWhatsApp,
    required this.sendWhatsApp,
    required this.onWhatsApp,
  });

  final ApptItem item;
  final DateTime slot;
  final bool showWhatsApp;
  final bool sendWhatsApp;
  final ValueChanged<bool> onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final time = ApptFormat.time(slot);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s14,
      ),
      decoration: ShapeDecoration(
        color: c.accentWash,
        shape: cruShape(CruRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Move ${item.firstName} to $time',
            style: CruType.callout.w600.tabular.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s2),
          Text(
            '${ApptFormat.pronoun(item)} booked later, and $time is the next '
            'free slot.',
            style: CruType.caption.tabular.tint(c.label2),
          ),
          if (showWhatsApp) ...[
            const SizedBox(height: CruSpace.s12),
            _CheckRow(
              label: 'Send ${item.firstName} the new time on WhatsApp',
              value: sendWhatsApp,
              onChanged: onWhatsApp,
            ),
          ],
        ],
      ),
    );
  }
}

/// An 18 px accent checkbox with its label.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Checkbox size and corner (no shared token; NEEDS.md).
  static const double _box = 18;
  static const double _radius = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      checked: value,
      label: label,
      excludeSemantics: true,
      child: CruPressable(
        onTap: () => onChanged(!value),
        scaleOnPress: false,
        builder: (context, hovered) => Row(
          children: [
            AnimatedContainer(
              duration: CruMotion.of(context, CruMotion.fast),
              curve: CruMotion.curve,
              width: _box,
              height: _box,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? c.accent : c.surface,
                borderRadius: BorderRadius.circular(_radius),
                border: value ? null : Border.all(color: c.label3),
              ),
              child: value
                  ? CruIcon(CruIcons.check, size: 13, strokeWidth: 2.6, color: c.onAccent)
                  : null,
            ),
            const SizedBox(width: CruSpace.s8),
            Expanded(
              child: Text(label, style: CruType.subhead.tint(c.label)),
            ),
          ],
        ),
      ),
    );
  }
}
