import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The 420 px preview beside (or over) the list: who, how to reach them,
/// money, visits and the last note.
class PatientPreviewPane extends ConsumerWidget {
  const PatientPreviewPane({
    super.key,
    required this.summary,
    required this.now,
    required this.onOpen,
    required this.onClose,
  });

  final PatientSummary summary;
  final DateTime now;

  /// ↗ and "Open full profile".
  final VoidCallback onOpen;

  /// × (Esc is handled by the screen).
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final s = summary;
    final clinic = ref.watch(doctorIdentityProvider).clinicName;
    final allergy = _allergyPill(ref);
    final phone = s.patient.phone.trim();

    final blocks = <Widget>[
      _Head(summary: s, onOpen: onOpen, onClose: onClose),
      if (allergy != null || phone.isNotEmpty)
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            ?allergy,
            if (phone.isNotEmpty)
              CruInfoPill(text: PatientFormat.phone(phone), tabular: true),
          ],
        ),
      _ActionTiles(summary: s),
      if (s.followUpOverdue) _FollowUpBlock(summary: s),
      if (s.hasBalance)
        _BalanceBlock(summary: s, clinicName: clinic)
      else
        const _PaidBlock(),
      if (s.completedCount > 0 || s.nextVisit != null)
        _VisitsBlock(summary: s, now: now),
      if (s.latestNote != null) ...[
        const CruSeparator(),
        _LastNote(summary: s, now: now),
      ],
      _OpenProfileButton(onPressed: onOpen),
    ];

    final pane = Semantics(
      container: true,
      label: 'Patient preview',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: cruShape(CruRadius.card, side: BorderSide(color: c.hairline)),
          shadows: c.paneShadow,
        ),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.all(CruSpace.s22 + 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) const SizedBox(height: CruSpace.s18),
                blocks[i],
              ],
            ],
          ),
        ),
      ),
    );

    // Slides in 16 px from the right and fades up; instant under
    // reduced motion. Swapping patients keeps the pane (no replay).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CruMotion.of(context, CruMotion.pane),
      curve: CruMotion.curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(CruSpace.s16 * (1 - t), 0),
          child: child,
        ),
      ),
      child: pane,
    );
  }

  /// Red "Allergic to …" when the case sheet records one, neutral "No
  /// known allergies" when it records a negative, hidden when unknown.
  Widget? _allergyPill(WidgetRef ref) {
    final sheet = ref.watch(homeopathyCaseSheetProvider(summary.id)).value;
    final text = sheet?.medicalHistory.allergies.trim() ?? '';
    if (text.isEmpty) return null;
    if (_isNegative(text)) {
      return const CruInfoPill(
        text: 'No known allergies',
        icon: CruIcons.check,
      );
    }
    return CruInfoPill(
      text: 'Allergic to $text',
      icon: CruIcons.warning,
      tone: CruInfoPillTone.allergy,
    );
  }

  static bool _isNegative(String raw) {
    final t = raw.toLowerCase().replaceAll(RegExp(r'[.\s]+$'), '').trim();
    const negatives = {
      'none',
      'nil',
      'no',
      'nkda',
      'nka',
      'n/a',
      'na',
      '-',
      '--',
      '—',
      'not known',
      'no allergies',
      'no allergy',
    };
    return negatives.contains(t) ||
        t.startsWith('no known') ||
        t.startsWith('none ') ||
        t.startsWith('nil ');
  }
}

class _Head extends StatelessWidget {
  const _Head({
    required this.summary,
    required this.onOpen,
    required this.onClose,
  });

  final PatientSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CruMonogram(name: summary.name, size: CruSize.monogramPreview),
        const SizedBox(width: CruSpace.s14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: CruSpace.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    summary.name,
                    style: CruType.title2.tint(c.label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Patient ID is a GAP.
                Text(
                  PatientFormat.ageSexLong(summary.patient),
                  style: CruType.chip
                      .copyWith(fontWeight: FontWeight.w400)
                      .tabular
                      .tint(c.label2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: CruSpace.s14),
        CruSquareButton(
          icon: CruIcons.arrowUpRight,
          semanticLabel: 'Open full profile',
          tooltip: 'Open full profile',
          onPressed: onOpen,
        ),
        const SizedBox(width: CruSpace.s14),
        CruSquareButton(
          icon: CruIcons.close,
          iconSize: 16,
          strokeWidth: 2.2,
          semanticLabel: 'Close preview',
          tooltip: 'Close',
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _ActionTiles extends ConsumerWidget {
  const _ActionTiles({required this.summary});

  final PatientSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = summary.patient;
    final hasPhone = p.phone.trim().isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: CruIcons.phone,
            label: 'Call',
            onTap: hasPhone ? () => PatientActions.call(context, p) : null,
          ),
        ),
        const SizedBox(width: CruSpace.s8),
        Expanded(
          child: _ActionTile(
            icon: CruIcons.whatsapp,
            label: 'WhatsApp',
            onTap: hasPhone ? () => PatientActions.whatsApp(context, p) : null,
          ),
        ),
        const SizedBox(width: CruSpace.s8),
        Expanded(
          child: _ActionTile(
            icon: CruIcons.calendar,
            label: 'New visit',
            onTap: () => PatientActions.newVisit(context, ref, p),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final CruIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final fg = onTap == null ? c.label3 : c.accentText;
    return CruPressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.actionTile,
        decoration: ShapeDecoration(
          color: hovered ? cruHoverShade(c.inset, c) : c.inset,
          shape: cruShape(CruRadius.control),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CruIcon(icon, size: 18, strokeWidth: 1.9, color: fg),
            const SizedBox(height: CruSpace.s4),
            Text(label, style: CruType.caption.w600.tint(fg), maxLines: 1),
          ],
        ),
      ),
    );
  }
}

/// Under Follow-up overdue this comes first and holds the one filled
/// button.
class _FollowUpBlock extends ConsumerWidget {
  const _FollowUpBlock({required this.summary});

  final PatientSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: ShapeDecoration(
        color: c.amberTint,
        shape: cruShape(CruRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Follow-up overdue since '
            '${PatientFormat.weekdayDate(summary.overdueSince!)}',
            style: CruType.callout.tabular.tint(c.amberText),
          ),
          const SizedBox(height: CruSpace.s12),
          CruButton(
            label: 'Book follow-up',
            large: true,
            expand: true,
            onPressed: () =>
                PatientActions.newVisit(context, ref, summary.patient),
          ),
        ],
      ),
    );
  }
}

class _BalanceBlock extends ConsumerWidget {
  const _BalanceBlock({required this.summary, required this.clinicName});

  final PatientSummary summary;
  final String? clinicName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final s = summary;
    final hasPhone = s.patient.phone.trim().isNotEmpty;
    // "₹paid of ₹total paid" and the paid bar are GAPs (no package total).
    return Container(
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Balance due', style: CruType.subhead.w500.tint(c.label2)),
          const SizedBox(height: CruSpace.s10),
          Text(
            PatientFormat.rupees(s.balance),
            style: CruType.amount.tint(c.label),
          ),
          const SizedBox(height: CruSpace.s14),
          CruButton(
            label: 'Record payment',
            large: true,
            expand: true,
            // One filled button per region: Book follow-up takes it.
            kind: s.followUpOverdue
                ? CruButtonKind.tinted
                : CruButtonKind.primary,
            onPressed: () => PatientActions.recordPayment(context, ref, s),
          ),
          if (hasPhone) ...[
            const SizedBox(height: CruSpace.s10),
            Center(
              child: CruLink(
                label: 'Send a payment reminder',
                onPressed: () => PatientActions.whatsApp(
                  context,
                  s.patient,
                  message: PatientActions.paymentReminderText(
                    s,
                    clinicName: clinicName,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaidBlock extends StatelessWidget {
  const _PaidBlock();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s14,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.panel),
      ),
      child: Row(
        children: [
          const CruDoneBadge(size: 18),
          const SizedBox(width: CruSpace.s10),
          Text('No balance due', style: CruType.text.w500.tint(c.label)),
        ],
      ),
    );
  }
}

/// Treatment plan is a GAP: "Visits · N completed · Next: …" instead.
class _VisitsBlock extends StatelessWidget {
  const _VisitsBlock({required this.summary, required this.now});

  final PatientSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = summary;
    final n = s.completedCount;
    final next = s.nextVisit;
    final overdue = s.overdueSince;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visits', style: CruType.subhead.w500.tint(c.label2)),
        const SizedBox(height: CruSpace.s4),
        Text(
          n == 0 ? 'None completed yet' : '$n completed',
          style: CruType.row.tabular.tint(c.label),
        ),
        if (next != null || overdue != null) ...[
          const SizedBox(height: CruSpace.s4),
          if (next != null)
            Text(
              'Next: ${PatientFormat.dayTimeInline(next.scheduledStart, now)}',
              style: CruType.subhead.tabular.tint(c.label2),
            )
          else
            Text(
              'Overdue since ${PatientFormat.weekdayDate(overdue!)}',
              style: CruType.subhead.w600.tabular.tint(c.amberText),
            ),
        ],
      ],
    );
  }
}

class _LastNote extends StatelessWidget {
  const _LastNote({required this.summary, required this.now});

  final PatientSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final visit = summary.latestNote!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'Last note',
                style: CruType.subhead.w500.tint(c.label2),
              ),
            ),
            Text(
              PatientFormat.dayTime(visit.scheduledStart, now),
              style: CruType.caption.tabular.tint(c.label3),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s4),
        Text(
          visit.therapistNotes!.trim(),
          style: CruType.note.tint(c.label),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// 40 px outline button with a trailing chevron.
class _OpenProfileButton extends StatelessWidget {
  const _OpenProfileButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: 'Open full profile',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: CruSize.control,
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.surface,
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(color: c.separator),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Open full profile', style: CruType.callout.tint(c.accentText)),
            const SizedBox(width: CruSpace.s4),
            CruIcon(
              CruIcons.chevronRight,
              size: 15,
              strokeWidth: 2.2,
              color: c.accentText,
            ),
          ],
        ),
      ),
    );
  }
}
