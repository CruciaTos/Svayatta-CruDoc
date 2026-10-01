import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_view_providers.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_builder.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_add_transaction_dialog.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Revenue: what came in for the period, who still owes, and every
/// transaction. Recording money is one tap from the header.
class MobileRevenueScreen extends ConsumerWidget {
  const MobileRevenueScreen({super.key});

  void _add(BuildContext context) => showMobileActionSheet(
    context,
    title: 'Record',
    actions: [
      MobileSheetAction(
        label: 'Payment received',
        icon: CruIcons.arrowDown,
        tone: MobileTone.green,
        onTap: () => showDesktopAddTransactionDialog(
          mobileRoot(context),
          initialKind: TransactionKind.income,
        ),
      ),
      MobileSheetAction(
        label: 'Expense',
        icon: CruIcons.arrowUp,
        tone: MobileTone.slate,
        onTap: () => showDesktopAddTransactionDialog(
          mobileRoot(context),
          initialKind: TransactionKind.expense,
        ),
      ),
      MobileSheetAction(
        label: 'Invoice',
        icon: CruIcons.fileText,
        tone: MobileTone.indigo,
        onTap: () => showDesktopCreateInvoiceDialog(mobileRoot(context)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final view = ref.watch(revenueViewControllerProvider);
    final o = ref.watch(revenueOverviewProvider);
    final pending = ref.watch(revenuePendingProvider);

    return ListView(
      padding: EdgeInsets.only(bottom: MobileMetrics.bottom(context)),
      children: [
        MobileHeader(
          title: 'Revenue',
          subtitle: o?.subtitle,
          trailing: MobileCircleButton(
            icon: CruIcons.plus,
            semanticLabel: 'Record a payment, expense or invoice',
            onPressed: () => _add(context),
          ),
        ),
        const SizedBox(height: CruSpace.s16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
          child: MobileSegmented<RevenuePeriod>(
            values: RevenuePeriod.values,
            label: (p) => switch (p) {
              RevenuePeriod.today => 'Today',
              RevenuePeriod.week => 'Week',
              RevenuePeriod.month => 'Month',
              RevenuePeriod.year => 'Year',
            },
            selected: view.period,
            onBand: true,
            onChanged: (p) =>
                ref.read(revenueViewControllerProvider.notifier).setPeriod(p),
          ),
        ),
        const SizedBox(height: CruSpace.s12),
        if (o == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
            child: MobileCard(
              child: MobileLoading('Loading revenue…', height: 220),
            ),
          )
        else
          _PeriodCards(
            period: view.period,
            onChanged: (p) =>
                ref.read(revenueViewControllerProvider.notifier).setPeriod(p),
          ),
        if (pending != null && pending.isNotEmpty) ...[
          const SizedBox(height: CruSpace.s16),
          MobileRowGroup(
            title:
                'To collect · ${DashFormat.rupeesCompact(pending.fold(0.0, (s, g) => s + g.total))}',

            children: [
              for (final g in pending.take(5))
                _PendingRow(
                  group: g,
                  clinic: ref.watch(doctorIdentityProvider).clinicName,
                ),
            ],
          ),
        ],
        const SizedBox(height: CruSpace.s16),
        MobileRowGroup(
          title: 'Transactions',
          action: 'Invoices',
          onAction: () => openMobileInvoices(context),
          children: o == null
              ? const [MobileLoading('Loading transactions…')]
              : o.transactions.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                    child: Text(
                      'Nothing recorded in this period',
                      style: MobileType.subhead.tint(c.label2),
                    ),
                  ),
                ]
              : [
                  for (final t in o.transactions.take(40))
                    MobileRow(
                      leading: MobileIconTile(
                        icon: t.moneyOut
                            ? CruIcons.arrowUp
                            : CruIcons.arrowDown,
                        tone: t.moneyOut ? MobileTone.slate : MobileTone.green,
                      ),
                      title: t.title,
                      subtitle:
                          '${t.dayLabel} · ${t.time} ${t.meridiem}'
                          '${t.subtitle.isEmpty ? '' : ' · ${t.subtitle}'}',
                      trailing: Text(
                        t.amount,
                        style: MobileType.callout.tabular.tint(
                          t.moneyOut
                              ? c.label
                              : mobileTone(c, MobileTone.green).$2,
                        ),
                      ),
                    ),
                ],
        ),
      ],
    );
  }
}

/// One period's figures, for its own card (all four cards stay built).
final _periodOverviewProvider =
    Provider.family<RevenueOverview?, RevenuePeriod>((ref, period) {
      final async = ref.watch(recentRevenueEntriesProvider);
      final entries = async.hasError ? const <RevenueEntry>[] : async.value;
      if (entries == null) return null;
      return RevenueBuilder.overview(
        entries: entries,
        period: period,
        filter: ref.watch(
          revenueViewControllerProvider.select((v) => v.filter),
        ),
        now: ref.watch(dashboardNowProvider),
      );
    });

/// A card for each period, side by side: swipe the card to slide to the
/// next period (the tabs only swipe from anywhere else). The period
/// buttons above slide the cards too. The next card peeks at the edge.
class _PeriodCards extends ConsumerStatefulWidget {
  const _PeriodCards({required this.period, required this.onChanged});

  final RevenuePeriod period;
  final ValueChanged<RevenuePeriod> onChanged;

  @override
  ConsumerState<_PeriodCards> createState() => _PeriodCardsState();
}

class _PeriodCardsState extends ConsumerState<_PeriodCards> {
  static const _values = RevenuePeriod.values;

  late final PageController _pages = PageController(
    initialPage: _values.indexOf(widget.period),
    viewportFraction: 0.9,
  );

  /// Each card's own height; the strip takes the height of the card in
  /// view (blended while sliding).
  final Map<int, double> _heights = {};

  /// True while the buttons drive the slide, so the cards passed on the
  /// way don't each become the period.
  bool _driving = false;

  @override
  void didUpdateWidget(_PeriodCards old) {
    super.didUpdateWidget(old);
    final i = _values.indexOf(widget.period);
    if (!_pages.hasClients || _pages.page?.round() == i) return;
    _driving = true;
    _pages
        .animateToPage(
          i,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _driving = false);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  double get _height {
    const fallback = 262.0;
    final page = _pages.hasClients && _pages.position.haveDimensions
        ? (_pages.page ?? 0)
        : _values.indexOf(widget.period).toDouble();
    final a = page.floor().clamp(0, _values.length - 1);
    final b = page.ceil().clamp(0, _values.length - 1);
    final ha = _heights[a] ?? _heights[b] ?? fallback;
    final hb = _heights[b] ?? ha;
    return ha + (hb - ha) * (page - a);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pages,
      builder: (context, child) => SizedBox(height: _height, child: child),
      child: PageView.builder(
        controller: _pages,
        itemCount: _values.length,
        clipBehavior: Clip.none,
        onPageChanged: (i) {
          if (_driving) return;
          MobileHaptics.select();
          widget.onChanged(_values[i]);
        },
        itemBuilder: (context, i) {
          final o = ref.watch(_periodOverviewProvider(_values[i]));
          return OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: _MeasureHeight(
              onHeight: (h) {
                if (!mounted || _heights[i] == h) return;
                setState(() => _heights[i] = h);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: o == null
                    ? const MobileCard(
                        child: MobileLoading('Loading revenue…', height: 220),
                      )
                    : RepaintBoundary(
                        child: _Hero(o: o, period: _values[i]),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Reports its child's laid-out height after each layout that changes it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}

/// A period card's colours, dark corner to bright edge, like a payment
/// card: Today green, Week blue, Month violet, Year orange.
List<Color> _cardInks(RevenuePeriod period) => switch (period) {
  RevenuePeriod.today => const [
    Color(0xFF0A0F0C),
    Color(0xFF0C3B27),
    Color(0xFF12A361),
    Color(0xFF45DE9C),
  ],
  RevenuePeriod.week => const [
    Color(0xFF0A0C14),
    Color(0xFF122C6E),
    Color(0xFF2F5BF0),
    Color(0xFF74A0FF),
  ],
  RevenuePeriod.month => const [
    Color(0xFF0E0A14),
    Color(0xFF3C1772),
    Color(0xFF7B40F2),
    Color(0xFFB892FF),
  ],
  RevenuePeriod.year => const [
    Color(0xFF120A08),
    Color(0xFF7A1F0C),
    Color(0xFFF0531B),
    Color(0xFFFF8C40),
  ],
};

/// Each period card's own pattern on its own colour: Today a diagonal
/// sweep with light streaks, Week rippled waves, Month glowing blobs,
/// One period's money as a payment card: what came in, its bars, and
/// expenses and net in the corner where a card number would be.
class _Hero extends StatelessWidget {
  const _Hero({required this.o, required this.period});

  final RevenueOverview o;
  final RevenuePeriod period;

  static const double _radius = 22;

  @override
  Widget build(BuildContext context) {
    final inks = _cardInks(period);
    final pct = o.comparison.percent;
    final up = (pct ?? 0) >= 0;
    final soft = Colors.white.withValues(alpha: 0.72);
    final quiet = Colors.white.withValues(alpha: 0.6);
    final amount = DashFormat.rupees(o.collected).replaceFirst('₹', '');
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: cruShape(_radius),
        shadows: [
          BoxShadow(
            color: inks[2].withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(_radius),
        // The card's pattern is a picture made once (it never changes),
        // so nothing is drawn for it while the cards slide.
        child: DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(
                'assets/images/revenue_cards/${period.name}.webp',
              ),
              fit: BoxFit.cover,
            ),
          ),
          child: DecoratedBox(
            // A soft light from the top right, and a hairline rim.
            decoration: ShapeDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.9, -1.1),
                radius: 0.9,
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
              shape: cruShape(
                _radius,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(switch (period) {
                          RevenuePeriod.today => 'Collected today',
                          RevenuePeriod.week => 'Collected this week',
                          RevenuePeriod.month => 'Collected this month',
                          RevenuePeriod.year => 'Collected this year',
                        }, style: MobileType.caption.w500.tint(soft)),
                      ),
                      if (pct != null)
                        Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: ShapeDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            shape: const StadiumBorder(),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CruIcon(
                                up ? CruIcons.arrowUp : CruIcons.arrowDown,
                                size: 12,
                                strokeWidth: 2.6,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${pct.abs()}% vs ${o.comparisonLabel}',
                                style: MobileType.micro.w600.tabular.tint(
                                  Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: CruSpace.s8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '₹',
                            style: MobileType.metric.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w400,
                              color: soft,
                            ),
                          ),
                          TextSpan(
                            text: amount,
                            style: MobileType.metric.copyWith(
                              fontSize: 38,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.6,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s14),
                  _Bars(chart: o.chart, onCard: true),
                  const SizedBox(height: CruSpace.s16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Expenses  ${DashFormat.rupeesCompact(o.expenses)}',
                              style: MobileType.micro.tabular
                                  .copyWith(letterSpacing: 0.6)
                                  .tint(quiet),
                            ),
                            const SizedBox(height: CruSpace.s2),
                            Text(
                              'Net  ${DashFormat.rupeesCompact(o.collected - o.expenses)}',
                              style: MobileType.caption.w500.tabular
                                  .copyWith(letterSpacing: 0.6)
                                  .tint(Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        switch (period) {
                          RevenuePeriod.today => 'TODAY',
                          RevenuePeriod.week => 'WEEK',
                          RevenuePeriod.month => 'MONTH',
                          RevenuePeriod.year => 'YEAR',
                        },
                        style: MobileType.headline.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The period's bars from the desktop chart data: today in the brand
/// blue, other days a lighter step of it.
class _Bars extends StatelessWidget {
  const _Bars({required this.chart, this.onCard = false});

  final ChartData chart;

  /// On a coloured period card: white bars, softer for past days.
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final bars = chart.bars;
    if (bars.isEmpty) return SizedBox(height: onCard ? 52 : 64);
    final h = onCard ? 48.0 : 60.0;
    final max = chart.scaleMax <= 0 ? 1.0 : chart.scaleMax;
    final dense = bars.length > 16;
    return SizedBox(
      height: h + 4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in bars)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: dense ? 1 : 3),
                child: Semantics(
                  label: b.semantic,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (b.amount / max).clamp(0.0, 1.0)),
                    duration: CruMotion.of(context),
                    curve: CruMotion.curve,
                    builder: (context, t, _) => Container(
                      height: switch (b.kind) {
                        BarKind.past || BarKind.today => 4 + h * t,
                        _ => 4,
                      },
                      decoration: BoxDecoration(
                        color: onCard
                            ? Colors.white.withValues(
                                alpha: switch (b.kind) {
                                  BarKind.today => 1,
                                  BarKind.past => 0.55,
                                  BarKind.emptyPast => 0.2,
                                  BarKind.future => 0.1,
                                },
                              )
                            : switch (b.kind) {
                                BarKind.today => c.barActive,
                                BarKind.past => c.barMuted,
                                BarKind.emptyPast => c.track,
                                BarKind.future => c.track.withValues(
                                  alpha: 0.5,
                                ),
                              },
                        borderRadius: BorderRadius.circular(dense ? 2 : 4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.group, required this.clinic});

  final PendingGroup group;
  final String? clinic;

  String get _message =>
      'Hello ${group.name.split(' ').first}, a gentle reminder of the '
      '${DashFormat.rupees(group.total)} pending'
      '${clinic == null ? '' : ' at $clinic'}. Thank you.';

  void _sheet(BuildContext context) {
    final p = group.patient;
    showMobileActionSheet(
      context,
      title: group.name,
      subtitle: '${DashFormat.rupees(group.total)} · ${group.detail}',
      leading: MobileAvatar(name: group.name, size: 34),
      actions: [
        if (group.canRemind)
          MobileSheetAction(
            label: 'Remind on WhatsApp',
            icon: CruIcons.whatsapp,
            tone: MobileTone.teal,
            onTap: () =>
                PatientActions.whatsApp(context, p!, message: _message),
          ),
        if (p != null && p.phone.trim().isNotEmpty)
          MobileSheetAction(
            label: 'Call',
            icon: CruIcons.phone,
            tone: MobileTone.green,
            onTap: () => PatientActions.call(context, p),
          ),
        if (p != null)
          MobileSheetAction(
            label: 'Open patient',
            icon: CruIcons.user,
            tone: MobileTone.blue,
            onTap: () => openMobilePatient(context, p),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return MobileRow(
      leading: MobileAvatar(name: group.name, size: 32),
      title: group.name,
      subtitle: group.detail,
      trailing: Text(
        DashFormat.rupees(group.total),
        style: MobileType.callout.tabular.tint(
          group.overdue ? mobileTone(c, MobileTone.amber).$2 : c.label,
        ),
      ),
      onTap: () => _sheet(context),
      onLongPress: () => _sheet(context),
    );
  }
}
