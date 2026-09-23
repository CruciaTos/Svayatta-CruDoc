import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/revenue/domain/revenue_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// Chart geometry from html/Revenue.dc.html (the card's 170 px plot).
// Not tokens yet; see NEEDS.md (Builder 4).

/// Tallest bar.
const double _plotHeight = 140;

/// Room above the tallest bar so the top tick label isn't clipped.
const double _plotTop = 10;

/// x label line.
const double _labelHeight = 14;

/// Width of the y label column.
const double _yLabelWidth = 28;

/// Where gridlines start (y labels + 8).
const double _gridLeft = 36;

/// Where bars start.
const double _barsLeft = 44;

/// A bar never gets wider than this (Week has 7, Year 12).
const double _maxBarWidth = 48;

/// Legend swatch.
const double _swatch = 10;

const double _chartHeight = _plotTop + _plotHeight + CruSpace.s6 + _labelHeight;

/// One bar per day of the period (per month on Year).
class CollectionsByDayCard extends StatelessWidget {
  const CollectionsByDayCard({super.key, required this.chart});

  final ChartData chart;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Collections by day',
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s24,
        CruSpace.s20,
        CruSpace.s24,
        CruSpace.s18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    chart.bars.length == 12 && chart.todayLegend == 'This month'
                        ? 'Collections by month'
                        : 'Collections by day',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
              ),
              if (chart.note != null)
                Text(chart.note!, style: CruType.subhead.tint(c.label2)),
            ],
          ),
          const SizedBox(height: CruSpace.s18),
          SizedBox(height: _chartHeight, child: _Chart(chart: chart)),
          const SizedBox(height: CruSpace.s18),
          Wrap(
            spacing: CruSpace.s18,
            runSpacing: CruSpace.s6,
            children: [
              _LegendItem(color: c.track, label: 'Collected'),
              _LegendItem(
                color: c.isEvening ? c.accentText : c.accent,
                label: '${chart.todayLegend} · ${DashFormat.rupees(chart.todayAmount)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.chart});
  final ChartData chart;

  double _y(double amount) =>
      _plotTop + _plotHeight - amount / chart.scaleMax * _plotHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Stack(
      children: [
        for (final t in chart.ticks) ...[
          Positioned(
            left: _gridLeft,
            right: 0,
            top: _y(t),
            height: 1,
            child: ColoredBox(color: c.separator),
          ),
          Positioned(
            left: 0,
            width: _yLabelWidth,
            top: _y(t) - _labelHeight / 2,
            height: _labelHeight,
            child: Text(
              DashFormat.rupeesCompact(t),
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: CruType.micro.tabular.tint(c.label3),
            ),
          ),
        ],
        Positioned(
          left: _barsLeft,
          right: 0,
          top: 0,
          bottom: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in chart.bars)
                Expanded(child: _Bar(bar: b, scaleMax: chart.scaleMax)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.bar, required this.scaleMax});

  final ChartBar bar;
  final double scaleMax;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final today = c.isEvening ? c.accentText : c.accent;
    final stub = bar.amount <= 0 || bar.kind == BarKind.future;
    final height = stub
        ? CruSize.barStub
        : (bar.amount / scaleMax * _plotHeight)
            .clamp(CruSize.barStub, _plotHeight)
            .toDouble();

    final Decoration decoration = switch (bar.kind) {
      BarKind.today => ShapeDecoration(
          color: today,
          shape: cruShape(stub ? CruRadius.barStub : CruRadius.bar),
        ),
      BarKind.past => ShapeDecoration(
          color: c.track,
          shape: cruShape(CruRadius.bar),
        ),
      BarKind.emptyPast => ShapeDecoration(
          color: c.track,
          shape: cruShape(CruRadius.barStub),
        ),
      BarKind.future => ShapeDecoration(
          shape: cruShape(
            CruRadius.barStub,
            side: BorderSide(color: c.separator),
          ),
        ),
    };

    return Semantics(
      label: bar.semantic,
      child: Padding(
        // Half the 4 px column gap on each side.
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxBarWidth),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: height),
                  duration: CruMotion.of(context),
                  curve: CruMotion.curve,
                  builder: (context, h, _) => Container(
                    width: double.infinity,
                    height: h,
                    decoration: decoration,
                  ),
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s6),
            SizedBox(
              height: _labelHeight,
              child: bar.label == null
                  ? null
                  : Text(
                      bar.label!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: (bar.isToday ? CruType.micro.w600 : CruType.micro)
                          .tabular
                          .tint(bar.isToday ? c.accentText : c.label3),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _swatch,
          height: _swatch,
          decoration: ShapeDecoration(
            color: color,
            shape: cruShape(CruRadius.thinBar),
          ),
        ),
        const SizedBox(width: CruSpace.s6),
        Text(label, style: CruType.caption.tabular.tint(c.label2)),
      ],
    );
  }
}

/// Loading placeholder with the card's final height.
class CollectionsByDaySkeleton extends StatelessWidget {
  const CollectionsByDaySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const CruCard(
      padding: EdgeInsets.fromLTRB(
        CruSpace.s24,
        CruSpace.s20,
        CruSpace.s24,
        CruSpace.s18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 160, height: 16),
          ),
          SizedBox(height: CruSpace.s18),
          SkeletonBox(height: _chartHeight),
          SizedBox(height: CruSpace.s18),
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 200, height: 12),
          ),
        ],
      ),
    );
  }
}
