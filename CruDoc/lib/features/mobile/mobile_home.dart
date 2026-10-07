import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/inventory/presentation/desktop_add_edit_medicine_dialog.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_add_transaction_dialog.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/scribe/presentation/scribe_recording_sheet.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_models.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/up_next_card.dart'
    show HomeVisitInk;
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/profile/presentation/profile_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

/// Home: who's next, how the day is going, and every common task one tap
/// away. Not a report: anything deeper is a tab or a tap further.
class MobileHomeScreen extends ConsumerWidget {
  const MobileHomeScreen({super.key, required this.enabledModules});

  final List<String> enabledModules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardDataProvider);
    final identity = ref.watch(doctorIdentityProvider);
    final name = identity.greetingName;
    final greeting = DashFormat.greeting(data.now);

    return ListView(
      padding: EdgeInsets.only(bottom: MobileMetrics.bottom(context)),
      children: [
        _HomeHeader(
          greeting: greeting,
          name: name ?? identity.fullName ?? 'Doctor',
        ),
        const SizedBox(height: CruSpace.s20),
        _QuickActions(modules: enabledModules),
        const SizedBox(height: CruSpace.s16),
        _GlanceRow(data: data),
        const SizedBox(height: CruSpace.s16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
          child: _NowCard(data: data),
        ),
        const SizedBox(height: CruSpace.s16),
        _TodayPreview(data: data),
        if (data.attention?.isNotEmpty ?? false) ...[
          const SizedBox(height: CruSpace.s16),
          _Attention(items: data.attention!),
        ],
      ],
    );
  }
}

void _toTab(WidgetRef ref, int tab) =>
    ref.read(mobileTabSwitcherProvider)?.call(tab);

/// Maps the desktop's tab jumps (used by shared actions) onto the phone.
void _navigateDesktopTab(WidgetRef ref, int desktopTab) =>
    _toTab(ref, switch (desktopTab) {
      DesktopTab.queue || DesktopTab.appointments => MobileTab.schedule,
      DesktopTab.patients => MobileTab.patients,
      DesktopTab.revenue => MobileTab.revenue,
      _ => MobileTab.home,
    });

/// The consultation in progress, if any (its queue token and visit).
ScheduleItem? _serving(DashboardData data) {
  for (final s in data.schedule ?? const <ScheduleItem>[]) {
    if (s.status == ScheduleStatus.inConsultation) return s;
  }
  return null;
}

/// The hero: the next patient on the ink card with one big Start, or a
/// quiet card when no one is waiting.
class _NowCard extends ConsumerWidget {
  const _NowCard({required this.data});

  final DashboardData data;

  Future<void> _finishAndStart(
    BuildContext context,
    WidgetRef ref,
    ScheduleItem serving,
    UpNextData? next,
  ) async {
    final repo = ref.read(queueRepositoryProvider);
    try {
      if (serving.queueEntryId != null) {
        await repo.complete(serving.queueEntryId!);
      }
      if (next == null) {
        if (context.mounted) mobileSay(context, '${serving.firstName} done.');
        return;
      }
      final called = await repo.callNext();
      await repo.startConsultation(called.id);
      if (context.mounted) {
        mobileSay(
          context,
          '${serving.firstName} done. Started with ${next.name}.',
        );
      }
    } catch (e) {
      if (context.mounted) mobileSay(context, 'Could not update the queue: $e');
    }
  }

  void _more(BuildContext context, WidgetRef ref, UpNextData u) {
    final p = u.patient;
    showMobileActionSheet(
      context,
      title: u.name,
      subtitle: u.details,
      leading: MobileAvatar(name: u.name, size: 34),
      actions: [
        if (p != null)
          MobileSheetAction(
            label: 'Open patient',
            icon: CruIcons.user,
            tone: MobileTone.blue,
            onTap: () => openMobilePatient(context, p),
          ),
        if (p != null && p.phone.trim().isNotEmpty)
          MobileSheetAction(
            label: 'Call',
            icon: CruIcons.phone,
            tone: MobileTone.green,
            onTap: () => PatientActions.call(context, p),
          ),
        MobileSheetAction(
          label: 'Not here yet',
          detail: 'Moves them out of the line; requeue from Schedule',
          icon: CruIcons.clock,
          tone: MobileTone.amber,
          onTap: () => DashboardActions.skip(context, ref, u),
        ),
        MobileSheetAction(
          label: 'Cancel token',
          icon: CruIcons.close,
          destructive: true,
          onTap: () => DashboardActions.cancel(context, ref, u),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    if (!data.scheduleReady) {
      // Loading: the Up next card's own shape, so nothing jumps when the
      // queue arrives.
      final onInk = c.onInk();
      return _Glow(
        child: CruInkCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Up next', style: MobileType.subhead.tint(onInk.label2)),
              const SizedBox(height: CruSpace.s14),
              const _Bone(width: 190, height: 22),
              const SizedBox(height: CruSpace.s10),
              const _Bone(width: 240, height: 14),
              const SizedBox(height: CruSpace.s20),
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onInk.label2,
                    ),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  Text(
                    "Loading today's queue…",
                    style: MobileType.subhead.tint(onInk.label2),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final up = data.upNext;
    final serving = _serving(data);

    if (up == null) {
      final line = serving != null
          ? 'With ${serving.name} now'
          : data.nextBooking != null
          ? 'Next booking at ${DashFormat.time(data.nextBooking!)}'
          : 'Nothing else booked today';
      return MobileCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _CardLabel('Up next'),
            const SizedBox(height: CruSpace.s8),
            MobileField(
              child: Row(
                children: [
                  MobileIconTile(
                    icon: serving != null ? CruIcons.user : CruIcons.clock,
                    tone: MobileTone.blue,
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No one waiting',
                          style: MobileType.row.tint(c.label),
                        ),
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MobileType.subhead.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s14),
            serving != null
                ? MobilePrimaryButton(
                    label: 'Finish ${serving.firstName}',
                    icon: CruIcons.check,
                    onPressed: () =>
                        _finishAndStart(context, ref, serving, null),
                  )
                : MobilePrimaryButton(
                    label: 'Check in a patient',
                    icon: CruIcons.userCheck,
                    onPressed: () => DashboardActions.newVisit(context),
                  ),
          ],
        ),
      );
    }

    // The ink card with white text.
    final onInk = c.onInk();
    // A physiotherapist's home visit: olive card with the address.
    final home = up.isHomeVisit && ref.watch(isPhysiotherapyProvider);
    final soft = home ? HomeVisitInk.accent : onInk.label2;
    return _Glow(
      child: CruInkCard(
        colors: home ? HomeVisitInk.gradient : null,
        borderColor: home ? HomeVisitInk.border : null,
        padding: const EdgeInsets.fromLTRB(20, 14, 10, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (home) ...[
                  CruIcon(CruIcons.home, size: 15, color: soft),
                  const SizedBox(width: CruSpace.s6),
                ],
                Text(
                  home
                      ? 'Home visit'
                      : serving != null
                      ? 'Next, after ${serving.firstName}'
                      : 'Up next',
                  style: MobileType.subhead.tint(soft),
                ),
                const Spacer(),
                if (up.tokenNumber != null)
                  _InkPill('Token ${up.tokenNumber}', color: onInk.label),
                CruIconButton(
                  icon: CruIcons.more,
                  size: 38,
                  iconSize: 18,
                  semanticLabel: 'More for ${up.name}',
                  onPressed: () => _more(context, ref, up),
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s6),
            Padding(
              padding: const EdgeInsets.only(right: CruSpace.s10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    up.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MobileType.title.tint(onInk.label),
                  ),
                  const SizedBox(height: CruSpace.s4),
                  Text(
                    up.details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MobileType.subhead.tint(soft),
                  ),
                  if (home && up.homeAddress != null) ...[
                    const SizedBox(height: CruSpace.s8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CruIcon(CruIcons.home, size: 14, color: soft),
                        ),
                        const SizedBox(width: CruSpace.s8),
                        Expanded(
                          child: Text(
                            up.homeAddress!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MobileType.subhead.tint(onInk.label),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: CruSpace.s12),
                  _InkPill(
                    'Waiting ${DashFormat.minutes(up.waitMinutes)}',
                    color: onInk.amberText,
                    icon: CruIcons.clock,
                  ),
                  const SizedBox(height: CruSpace.s16),
                  _InkButton(
                    label: serving != null
                        ? 'Finish & start ${_first(up.name)}'
                        : home
                        ? 'Start session'
                        : 'Start consultation',
                    icon: CruIcons.play,
                    onPressed: () {
                      if (serving != null) {
                        _finishAndStart(context, ref, serving, up);
                      } else {
                        DashboardActions.startConsultation(
                          context,
                          ref,
                          up,
                          navigate: (t) => _navigateDesktopTab(ref, t),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _first(String name) => name.trim().split(RegExp(r'\s+')).first;
}

/// A faint light halo around the Up next card.
class _Glow extends StatelessWidget {
  const _Glow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      shape: cruShape(CruRadius.card),
      shadows: context.cru.isEvening
          ? const []
          : [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.15),
                blurRadius: 10,
              ),
            ],
    ),
    child: child,
  );
}

/// A soft bar standing in for text while it loads.
class _Bone extends StatelessWidget {
  const _Bone({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}

/// A small see-through pill on the ink card.
class _InkPill extends StatelessWidget {
  const _InkPill(this.text, {required this.color, this.icon});

  final String text;
  final Color color;
  final CruIconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            CruIcon(icon!, size: 14, strokeWidth: 2.2, color: color),
            const SizedBox(width: CruSpace.s6),
          ],
          Text(text, style: MobileType.caption.w600.tabular.tint(color)),
        ],
      ),
    );
  }
}

/// The ink card's action: see-through with a white border, not a white
/// block.
class _InkButton extends StatelessWidget {
  const _InkButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final CruIconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CruPressable(
      onTap: () {
        MobileHaptics.commit();
        onPressed();
      },
      semanticLabel: label,
      builder: (context, _) => Container(
        height: 52,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s20),
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: StadiumBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1.4,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruIcon(icon, size: 16, strokeWidth: 2.4, color: Colors.white),
            const SizedBox(width: CruSpace.s8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MobileType.callout.copyWith(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home's top: "Good afternoon," over the doctor's name, and their
/// avatar, which opens their profile.
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.greeting, required this.name});

  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MobileMetrics.gutter + CruSpace.s2,
        MobileMetrics.top(context) + CruSpace.s4,
        MobileMetrics.gutter,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting,',
                  style: MobileType.text.tint(
                    mobileInk(context).withValues(alpha: 0.65),
                  ),
                ),
                Text(
                  '$name!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MobileType.title2.tint(mobileInk(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruPressable(
            onTap: () => pushMobile(context, const ProfileScreen()),
            semanticLabel: 'Your profile',
            builder: (context, _) => MobileAvatar(name: name, size: 38),
          ),
        ],
      ),
    );
  }
}

/// The small grey label at the top of a card ("Up next").
class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: MobileType.subhead.tint(context.cru.label2));
}

/// Three numbers for the day; each opens the tab behind it.
class _GlanceRow extends ConsumerWidget {
  const _GlanceRow({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final g = data.glance;
    final collected = data.collected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      child: Row(
        children: [
          Expanded(
            child: _Glance(
              label: 'Seen',
              value: g == null ? '–' : '${g.seen}',
              suffix: g == null ? null : '/${g.total}',
              trailing: g == null
                  ? null
                  : CruProgressRing(
                      value: g.progress,
                      size: 22,
                      strokeWidth: 3.5,
                    ),
              onTap: () => _toTab(ref, MobileTab.schedule),
            ),
          ),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: _Glance(
              label: 'Waiting',
              value: g == null ? '–' : '${g.waiting}',
              valueColor: (g?.waiting ?? 0) > 0
                  ? mobileTone(c, MobileTone.amber).$2
                  : null,
              caption: g?.averageWaitMinutes == null || g!.waiting == 0
                  ? null
                  : '~${DashFormat.minutes(g.averageWaitMinutes!)}',
              onTap: () => _toTab(ref, MobileTab.schedule),
            ),
          ),
          if (ref.watch(clinicCanProvider(ClinicPermission.revenue))) ...[
            const SizedBox(width: CruSpace.s10),
            Expanded(
              child: _Glance(
                label: 'Collected',
                value: collected == null
                    ? '–'
                    : DashFormat.rupeesCompact(collected.today),
                valueColor: (collected?.today ?? 0) > 0
                    ? mobileTone(c, MobileTone.green).$2
                    : null,
                onTap: () => _toTab(ref, MobileTab.revenue),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Glance extends StatelessWidget {
  const _Glance({
    required this.label,
    required this.value,
    required this.onTap,
    this.suffix,
    this.caption,
    this.trailing,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? suffix;
  final String? caption;
  final Widget? trailing;
  final Color? valueColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return MobileCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: MobileType.caption.w500.tint(c.label2),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: CruSpace.s6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: MobileType.metric.copyWith(
                      color: valueColor ?? c.label,
                    ),
                  ),
                  if (suffix != null)
                    TextSpan(
                      text: suffix,
                      style: MobileType.metricSuffix.copyWith(color: c.label3),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 16,
            child: caption == null
                ? null
                : Text(
                    caption!,
                    style: MobileType.caption.tabular.tint(c.label3),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.icon, this.tone, this.run);
  final String label;
  final CruIconData icon;
  final MobileTone tone;
  final Future<void> Function(BuildContext context, WidgetRef ref) run;
}

/// The everyday "make something" tasks: two rows of four big tiles within
/// thumb reach. Each one opens its form straight away.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.modules});

  final List<String> modules;

  static Future<void> _bookVisit(BuildContext context, WidgetRef ref) async {
    final root = mobileRoot(context);
    final patient = await showPatientPickerDialog(
      root,
      title: 'Book a visit for',
    );
    if (patient == null || !root.mounted) return;
    await showScheduleVisitSheet(
      root,
      patient: patient,
      visitRepository: ref.read(visitRepositoryProvider),
    );
  }

  /// Scribe writes up the consultation in progress; with none, its list.
  static Future<void> _dictate(BuildContext context, WidgetRef ref) async {
    final today = DateTime.now();
    final items =
        ref
            .read(
              apptDayItemsProvider(
                DateTime(today.year, today.month, today.day),
              ),
            )
            .value ??
        const <ApptItem>[];
    for (final i in items) {
      if (i.status == ApptStatus.inConsultation) {
        await showScribeFlow(
          mobileRoot(context),
          visit: i.visit,
          patient: i.patient,
        );
        return;
      }
    }
    if (context.mounted) openMobileDestination(context, DesktopTab.scribe);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool on(String m) => DoctorFeatureGuard.isEnabled(modules, m);
    final actions = [
      _Action(
        'Check in',
        CruIcons.userCheck,
        MobileTone.amber,
        (ctx, _) => DashboardActions.newVisit(ctx),
      ),
      _Action('Book visit', CruIcons.calendar, MobileTone.blue, _bookVisit),
      _Action(
        'New patient',
        CruIcons.userPlus,
        MobileTone.sky,
        (ctx, _) => DashboardActions.addPatient(ctx),
      ),
      if (on('revenue')) ...[
        _Action(
          'Payment',
          CruIcons.rupee,
          MobileTone.green,
          (ctx, _) => showDesktopAddTransactionDialog(
            mobileRoot(ctx),
            initialKind: TransactionKind.income,
          ),
        ),
        _Action(
          'Invoice',
          CruIcons.fileText,
          MobileTone.indigo,
          (ctx, _) => showDesktopCreateInvoiceDialog(mobileRoot(ctx)),
        ),
      ],
      if (on('ai_assistant'))
        _Action('Dictate', CruIcons.mic, MobileTone.violet, _dictate),
      if (on('revenue'))
        _Action(
          'Expense',
          CruIcons.wallet,
          MobileTone.blue,
          (ctx, _) => showDesktopAddTransactionDialog(
            mobileRoot(ctx),
            initialKind: TransactionKind.expense,
          ),
        ),
      if (on('inventory'))
        _Action(
          'Medicine',
          CruIcons.box,
          MobileTone.teal,
          (ctx, _) => showDesktopAddEditMedicineDialog(mobileRoot(ctx)),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      // No fill, shadow or border: the tiles sit straight on the background.
      child: Padding(
        padding: const EdgeInsets.only(bottom: CruSpace.s18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MobileGroupTitle('Quick actions', onBackground: true),
            const SizedBox(height: CruSpace.s10),
            LayoutBuilder(
              builder: (context, box) {
                const gap = CruSpace.s10;
                final width = (box.maxWidth - gap * 3) / 4;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      SizedBox(
                        width: width,
                        child: _ActionTile(action: actions[i], index: i),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One quick action: a rounded square in the unified payment button
/// gradient (royal blue) with a white glyph, its label underneath straight on
/// the background.
class _ActionTile extends ConsumerWidget {
  const _ActionTile({required this.action, required this.index});

  final _Action action;

  /// Position in the grid.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CruPressable(
      onTap: () {
        MobileHaptics.tap();
        action.run(context, ref);
      },
      semanticLabel: action.label,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final side = box.maxWidth * 0.84;
          final (top, bottom) = mobileQuickActionGradient(index);
          return Column(
            children: [
              Container(
                width: side,
                height: side,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [top, bottom],
                  ),
                  shape: cruShape(side * 0.3),
                ),
                child: CruIcon(
                  action.icon,
                  size: side * 0.4,
                  strokeWidth: 1.8,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: CruSpace.s8),
              Text(
                action.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: MobileType.subhead.tint(mobileInk(context)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The next few people today; the whole list is on Schedule.
class _TodayPreview extends ConsumerWidget {
  const _TodayPreview({required this.data});

  final DashboardData data;

  static const _shown = 4;

  void _sheet(BuildContext context, ScheduleItem s) {
    final p = s.patient;
    if (p == null) return;
    showMobileActionSheet(
      context,
      title: s.name,
      subtitle: [?s.ageSex, ?s.reason].join(' · '),
      leading: MobileAvatar(name: s.name, size: 34),
      actions: [
        MobileSheetAction(
          label: 'Open patient',
          icon: CruIcons.user,
          tone: MobileTone.blue,
          onTap: () => openMobilePatient(context, p),
        ),
        if (p.phone.trim().isNotEmpty) ...[
          MobileSheetAction(
            label: 'Call',
            icon: CruIcons.phone,
            tone: MobileTone.green,
            onTap: () => PatientActions.call(context, p),
          ),
          MobileSheetAction(
            label: 'WhatsApp',
            icon: CruIcons.whatsapp,
            tone: MobileTone.teal,
            onTap: () => PatientActions.whatsApp(context, p),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final all = data.schedule;
    final open = [
      for (final s in all ?? const <ScheduleItem>[])
        if (s.status.isOpen && s.status != ScheduleStatus.inConsultation) s,
    ];
    final left = open.length - _shown;
    return MobileRowGroup(
      title: 'Still to see',
      action: 'Schedule',
      onAction: () => _toTab(ref, MobileTab.schedule),
      indent: 88,
      children: all == null
          ? const [MobileLoading('Loading today…')]
          : open.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                child: Text(
                  all.isEmpty ? 'Nothing booked today' : 'Everyone is seen',
                  style: MobileType.subhead.tint(c.label2),
                ),
              ),
            ]
          : [
              for (final s in open.take(_shown))
                MobileRow(
                  leading: SizedBox(
                    width: 60,
                    child: Text(
                      DashFormat.time(s.time),
                      style: MobileType.subhead.w600.tabular.tint(c.label2),
                    ),
                  ),
                  title: s.name,
                  subtitle: [?s.reason, ?s.kindLabel].firstOrNull ?? s.ageSex,
                  trailing: switch (s.status) {
                    ScheduleStatus.waiting => MobilePill(
                      s.waitMinutes == null
                          ? 'Waiting'
                          : DashFormat.minutes(s.waitMinutes!),
                      tone: MobileTone.amber,
                      icon: CruIcons.clock,
                    ),
                    ScheduleStatus.called => const MobilePill(
                      'Called',
                      tone: MobileTone.blue,
                    ),
                    ScheduleStatus.skipped => const MobilePill(
                      'Not here',
                      tone: MobileTone.slate,
                    ),
                    _ => null,
                  },
                  onTap: s.patient == null
                      ? null
                      : () => openMobilePatient(context, s.patient!),
                  onLongPress: s.patient == null
                      ? null
                      : () => _sheet(context, s),
                ),
              if (left > 0)
                MobileRow(
                  title: '$left more today',
                  titleStyle: MobileType.subhead.w600.tint(c.accentText),
                  chevron: true,
                  onTap: () => _toTab(ref, MobileTab.schedule),
                ),
            ],
    );
  }
}

/// Stock that needs a decision (low or expiring).
class _Attention extends StatelessWidget {
  const _Attention({required this.items});

  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileRowGroup(
          title: 'Needs attention',
          action: 'Inventory',
          onAction: () => openMobileDestination(context, DesktopTab.inventory),

          children: [
            for (final a in items.take(3))
              MobileRow(
                leading: MobileIconTile(
                  icon: a.kind == AttentionKind.lowStock
                      ? CruIcons.box
                      : CruIcons.clock,
                  tone: MobileTone.amber,
                ),
                title: a.title,
                subtitle: a.subtitle,
                chevron: true,
                onTap: () =>
                    openMobileDestination(context, DesktopTab.inventory),
              ),
          ],
        ),
      ],
    );
  }
}
