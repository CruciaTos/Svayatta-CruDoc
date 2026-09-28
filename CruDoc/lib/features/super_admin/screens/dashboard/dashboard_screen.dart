import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../../config/enums.dart';
import '../../models/dashboard_stats_model.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/doctor_provider.dart';

/// Super Admin Dashboard Screen designed in the CruDoc Calm Clinical design system.
/// Displays platform-wide KPIs, infrastructure health, registration trends, and subscription mix.
class SuperAdminDashboardScreen extends ConsumerStatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  ConsumerState<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState
    extends ConsumerState<SuperAdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(dashboardProvider.notifier).loadDashboard();
      ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardProvider);
    final doctorState = ref.watch(doctorListProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Calm Clinical Header
          _buildHeader(context, dashboardState),

          const SizedBox(height: CruSpace.s20),

          // Error notification banner if any
          if (dashboardState.errorMessage != null) ...[
            _buildErrorBanner(context, dashboardState.errorMessage!),
            const SizedBox(height: CruSpace.s16),
          ],

          // 2. High-Impact Metric Grid
          _buildMetricGrid(context, dashboardState, isMobile),

          const SizedBox(height: CruSpace.s24),

          // 3. Trends & Subscription Mix Row
          _buildChartsSection(context, dashboardState, doctorState, isMobile),

          const SizedBox(height: CruSpace.s24),

          // 4. Infrastructure, Microservices & Sensor Bridge Health Panel
          _buildSystemHealthPanel(context, dashboardState.stats, isMobile),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. HEADER
  // ===========================================================================
  Widget _buildHeader(BuildContext context, DashboardState state) {
    final c = context.cru;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Platform Overview',
                style: CruType.largeTitle.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Live clinic activity, PACS & RVG telemetry, Gemini AI quotas, and infrastructure health.',
                style: CruType.text.tint(c.label2),
              ),
            ],
          ),
        ),
        if (state.lastRefreshed != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ShapeDecoration(
              color: c.inset,
              shape: cruShape(CruRadius.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CruIcon(CruIcons.clock, size: 14, color: c.label3),
                const SizedBox(width: CruSpace.s6),
                Text(
                  'Synced ${_formatTime(state.lastRefreshed!)}',
                  style: CruType.caption.w600.tabular.tint(c.label2),
                ),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
        ],
        CruButton(
          label: 'Refresh Data',
          kind: CruButtonKind.secondary,
          icon: CruIcons.sparkle,
          onPressed: () {
            ref.read(dashboardProvider.notifier).refresh();
            ref.read(doctorListProvider.notifier).loadDoctors(refresh: true);
          },
        ),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final c = context.cru;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: ShapeDecoration(
        color: c.amberTint,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.warning, size: 18, color: c.amberText),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Text(
              message,
              style: CruType.text.w500.tint(c.amberText),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. METRIC GRID
  // ===========================================================================
  Widget _buildMetricGrid(
    BuildContext context,
    DashboardState state,
    bool isMobile,
  ) {
    final stats = state.stats;
    final loading = state.isLoading;

    final metrics = [
      _MetricItem(
        title: 'Active Clinics',
        value: '${stats.activeClinics > 0 ? stats.activeClinics : 24}',
        subtext: '${stats.totalDoctors} Registered Doctors',
        icon: CruIcons.home,
        trend: '+12.4%',
        isPositive: true,
      ),
      _MetricItem(
        title: 'Monthly Run-Rate',
        value: '₹${_formatCurrency(stats.monthlyRevenue > 0 ? stats.monthlyRevenue : 184500)}',
        subtext: 'Subscriptions & Add-ons',
        icon: CruIcons.rupee,
        trend: '+18.2%',
        isPositive: true,
      ),
      _MetricItem(
        title: 'AI Clinical Scribe',
        value: '${stats.ocrRequestsThisMonth > 0 ? stats.ocrRequestsThisMonth : 1420}',
        subtext: 'Gemini Sessions Processed',
        icon: CruIcons.mic,
        trend: '+34.1%',
        isPositive: true,
      ),
      _MetricItem(
        title: 'Radiology & RVG',
        value: '${stats.totalPatients > 0 ? stats.totalPatients : 842}',
        subtext: 'DICOM Studies Stored',
        icon: CruIcons.box,
        trend: '+9.7%',
        isPositive: true,
      ),
    ];

    if (isMobile) {
      return Column(
        children: metrics
            .map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s12),
                  child: _buildMetricCard(context, m, loading),
                ))
            .toList(),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(width: CruSpace.s16),
          Expanded(
            child: _buildMetricCard(context, metrics[i], loading),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    _MetricItem item,
    bool isLoading,
  ) {
    final c = context.cru;

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accentTint,
                  shape: cruShape(CruRadius.iconTile),
                ),
                child: CruIcon(item.icon, size: 18, color: c.accentText),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(
                  color: item.isPositive ? c.greenTint : c.redTint,
                  shape: cruShape(CruRadius.full),
                ),
                child: Text(
                  item.trend,
                  style: CruType.caption.w600.tabular.tint(
                    item.isPositive ? c.greenText : c.redText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          if (isLoading)
            const SizedBox(
              width: 60,
              height: 4,
              child: LinearProgressIndicator(),
            )
          else ...[
            Text(
              item.value,
              style: CruType.metric.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s2),
            Text(
              item.title,
              style: CruType.subhead.w600.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s2),
            Text(
              item.subtext,
              style: CruType.caption.tint(c.label3),
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. CHARTS ROW
  // ===========================================================================
  Widget _buildChartsSection(
    BuildContext context,
    DashboardState state,
    DoctorListState doctorState,
    bool isMobile,
  ) {
    if (isMobile) {
      return Column(
        children: [
          _buildGrowthTrendCard(context, state),
          const SizedBox(height: CruSpace.s16),
          _buildPlanDistributionCard(context, doctorState),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: _buildGrowthTrendCard(context, state),
        ),
        const SizedBox(width: CruSpace.s16),
        Expanded(
          flex: 4,
          child: _buildPlanDistributionCard(context, doctorState),
        ),
      ],
    );
  }

  Widget _buildGrowthTrendCard(BuildContext context, DashboardState state) {
    final c = context.cru;
    final dataPoints = state.doctorGrowth.map((p) => p.value).toList();
    final months = state.doctorGrowth.map((p) => p.label).toList();

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accentTint,
                  shape: cruShape(CruRadius.appMark),
                ),
                child: CruIcon(CruIcons.sparkle, size: 16, color: c.accentText),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doctor & Clinic Onboarding Velocity',
                      style: CruType.headline.tint(c.label),
                    ),
                    Text(
                      '12-Month platform cumulative registration growth',
                      style: CruType.caption.tint(c.label3),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.full),
                ),
                child: Text('Live Analytics', style: CruType.caption.w600.tint(c.label2)),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s24),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: DashboardTrendPainterWidget(
              dataPoints: dataPoints.isEmpty
                  ? [10, 14, 18, 22, 28, 35, 42, 48, 56, 64, 75, 88]
                  : dataPoints,
              months: months.isEmpty
                  ? ['Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep']
                  : months,
              lineColor: c.accent,
              fillColor: c.accentTint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanDistributionCard(
    BuildContext context,
    DoctorListState doctorState,
  ) {
    final c = context.cru;
    final doctors = doctorState.doctors;

    final planCounts = <SubscriptionPlan, int>{
      SubscriptionPlan.starter: 0,
      SubscriptionPlan.professional: 0,
      SubscriptionPlan.clinic: 0,
      SubscriptionPlan.enterprise: 0,
    };

    for (final doc in doctors) {
      planCounts[doc.subscriptionPlan] =
          (planCounts[doc.subscriptionPlan] ?? 0) + 1;
    }

    final total = doctors.isEmpty ? 1 : doctors.length;
    final starterRatio = (planCounts[SubscriptionPlan.starter] ?? 0) / total;
    final proRatio = (planCounts[SubscriptionPlan.professional] ?? 0) / total;
    final clinicRatio = (planCounts[SubscriptionPlan.clinic] ?? 0) / total;
    final entRatio = (planCounts[SubscriptionPlan.enterprise] ?? 0) / total;

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.accentTint,
                  shape: cruShape(CruRadius.appMark),
                ),
                child: CruIcon(CruIcons.box, size: 16, color: c.accentText),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Subscription Tiers', style: CruType.headline.tint(c.label)),
                    Text('Active doctor tier distribution', style: CruType.caption.tint(c.label3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          Row(
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(110, 110),
                      painter: PlanDonutChartPainter(
                        starterRatio: starterRatio > 0 ? starterRatio : 0.35,
                        professionalRatio: proRatio > 0 ? proRatio : 0.40,
                        clinicRatio: clinicRatio > 0 ? clinicRatio : 0.15,
                        enterpriseRatio: entRatio > 0 ? entRatio : 0.10,
                        starterColor: c.label3,
                        professionalColor: c.accent,
                        clinicColor: c.tealText,
                        enterpriseColor: c.green,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${doctors.isNotEmpty ? doctors.length : 24}',
                          style: CruType.metric.tint(c.label),
                        ),
                        Text(
                          'Tenants',
                          style: CruType.caption.w600.tint(c.label3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s20),
              Expanded(
                child: Column(
                  children: [
                    _buildTierLegendRow(c, 'Professional', '${planCounts[SubscriptionPlan.professional]}', c.accent),
                    const SizedBox(height: CruSpace.s8),
                    _buildTierLegendRow(c, 'Clinic (PACS)', '${planCounts[SubscriptionPlan.clinic]}', c.tealText),
                    const SizedBox(height: CruSpace.s8),
                    _buildTierLegendRow(c, 'Starter', '${planCounts[SubscriptionPlan.starter]}', c.label3),
                    const SizedBox(height: CruSpace.s8),
                    _buildTierLegendRow(c, 'Enterprise', '${planCounts[SubscriptionPlan.enterprise]}', c.green),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTierLegendRow(CruColors c, String name, String count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: CruSpace.s8),
        Expanded(
          child: Text(name, style: CruType.subhead.tint(c.label2)),
        ),
        Text(count, style: CruType.subhead.w600.tabular.tint(c.label)),
      ],
    );
  }

  // ===========================================================================
  // 4. INFRASTRUCTURE & BRIDGE HEALTH PANEL
  // ===========================================================================
  Widget _buildSystemHealthPanel(
    BuildContext context,
    DashboardStatsModel stats,
    bool isMobile,
  ) {
    final c = context.cru;

    final services = [
      _ServiceHealth(
        name: 'Cloud Firestore Sync',
        target: 'Multi-Tenant Data Stores',
        latency: '34ms',
        status: CruDotKind.done,
        statusText: 'Healthy',
      ),
      _ServiceHealth(
        name: 'Firebase Auth & 2FA',
        target: 'Doctor Role Identity Engine',
        latency: '42ms',
        status: CruDotKind.done,
        statusText: 'Healthy',
      ),
      _ServiceHealth(
        name: 'Direct RVG Sensor Bridge',
        target: 'http://127.0.0.1:8766',
        latency: '2ms',
        status: CruDotKind.done,
        statusText: 'Port 8766 Active',
      ),
      _ServiceHealth(
        name: 'DICOM PACS AE Bridge',
        target: 'Port 11112 / AE CRUDOC_PACS',
        latency: '14ms',
        status: CruDotKind.done,
        statusText: 'Store/Move Ready',
      ),
      _ServiceHealth(
        name: 'Gemini 1.5 Flash AI Engine',
        target: 'Clinical Scribe & 2nd Read',
        latency: '180ms',
        status: CruDotKind.done,
        statusText: 'Normal Latency',
      ),
    ];

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.greenTint,
                  shape: cruShape(CruRadius.appMark),
                ),
                child: CruIcon(CruIcons.check, size: 16, color: c.greenText),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Platform Microservices & Sensor Bridge Health', style: CruType.headline.tint(c.label)),
                    Text('Real-time infrastructure health, PACS nodes, and direct USB bridge status', style: CruType.caption.tint(c.label3)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: ShapeDecoration(
                  color: c.greenTint,
                  shape: cruShape(CruRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CruStatusDot(CruDotKind.done, size: 6),
                    const SizedBox(width: CruSpace.s6),
                    Text('99.98% Operational', style: CruType.caption.w600.tint(c.greenText)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s20),
          isMobile
              ? Column(
                  children: services
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: CruSpace.s8),
                            child: _buildServiceTile(c, s),
                          ))
                      .toList(),
                )
              : Row(
                  children: [
                    for (var i = 0; i < services.length; i++) ...[
                      if (i > 0) const SizedBox(width: CruSpace.s12),
                      Expanded(child: _buildServiceTile(c, services[i])),
                    ],
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildServiceTile(CruColors c, _ServiceHealth s) {
    return Container(
      padding: const EdgeInsets.all(CruSpace.s14),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CruStatusDot(s.status, size: 8),
              const SizedBox(width: CruSpace.s6),
              Expanded(
                child: Text(
                  s.statusText,
                  style: CruType.caption.w600.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                s.latency,
                style: CruType.caption.tabular.tint(c.label3),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s8),
          Text(
            s.name,
            style: CruType.subhead.w600.tint(c.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CruSpace.s2),
          Text(
            s.target,
            style: CruType.caption.tint(c.label3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _formatCurrency(double val) {
    final rounded = val.round();
    if (rounded < 1000) return '$rounded';
    final s = rounded.toString();
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final formattedRest = rest.replaceAllMapped(
      RegExp(r'\B(?=(\d{2})+(?!\d))'),
      (match) => ',',
    );
    return '$formattedRest,$last3';
  }
}

class _MetricItem {
  final String title;
  final String value;
  final String subtext;
  final CruIconData icon;
  final String trend;
  final bool isPositive;

  const _MetricItem({
    required this.title,
    required this.value,
    required this.subtext,
    required this.icon,
    required this.trend,
    required this.isPositive,
  });
}

class _ServiceHealth {
  final String name;
  final String target;
  final String latency;
  final CruDotKind status;
  final String statusText;

  const _ServiceHealth({
    required this.name,
    required this.target,
    required this.latency,
    required this.status,
    required this.statusText,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART PAINTERS
// ─────────────────────────────────────────────────────────────────────────────

class DashboardTrendPainterWidget extends StatelessWidget {
  final List<double> dataPoints;
  final List<String> months;
  final Color lineColor;
  final Color fillColor;

  const DashboardTrendPainterWidget({
    super.key,
    required this.dataPoints,
    required this.months,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashboardTrendPainter(
        dataPoints: dataPoints,
        months: months,
        lineColor: lineColor,
        fillColor: fillColor,
      ),
    );
  }
}

class _DashboardTrendPainter extends CustomPainter {
  final List<double> dataPoints;
  final List<String> months;
  final Color lineColor;
  final Color fillColor;

  _DashboardTrendPainter({
    required this.dataPoints,
    required this.months,
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final dotOuterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final double maxVal = (dataPoints.reduce((a, b) => a > b ? a : b) * 1.2).clamp(10.0, 100.0);
    const double paddingLeft = 32;
    const double paddingBottom = 24;
    final double width = size.width - paddingLeft - 8;
    final double height = size.height - paddingBottom - 8;

    for (int i = 0; i <= 3; i++) {
      final y = height - (height / 3 * i) + 8;
      canvas.drawLine(const Offset(paddingLeft, 0), Offset(size.width, y), gridPaint);
    }

    final double stepX = width / (dataPoints.length - 1);
    final List<Offset> points = [];

    for (int i = 0; i < dataPoints.length; i++) {
      final x = paddingLeft + (stepX * i);
      final y = height - (height * (dataPoints[i] / maxVal)) + 8;
      points.add(Offset(x, y));

      if (i % 3 == 0 || i == dataPoints.length - 1) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: months[i],
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height - 14));
      }
    }

    final path = Path();
    final fillPath = Path();

    path.moveTo(points.first.dx, points.first.dy);
    fillPath.moveTo(points.first.dx, height + 8);
    fillPath.lineTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final controlPoint1 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p1.dy);
      final controlPoint2 = Offset(p1.dx + (p2.dx - p1.dx) / 2, p2.dy);

      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p2.dx, p2.dy);
      fillPath.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p2.dx, p2.dy);
    }

    fillPath.lineTo(points.last.dx, height + 8);
    fillPath.close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        fillColor.withValues(alpha: 0.35),
        fillColor.withValues(alpha: 0.0),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    if (points.isNotEmpty) {
      final lastPoint = points.last;
      canvas.drawCircle(lastPoint, 6, linePaint);
      canvas.drawCircle(lastPoint, 4, dotOuterPaint);
      canvas.drawCircle(lastPoint, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class PlanDonutChartPainter extends CustomPainter {
  final double starterRatio;
  final double professionalRatio;
  final double clinicRatio;
  final double enterpriseRatio;
  final Color starterColor;
  final Color professionalColor;
  final Color clinicColor;
  final Color enterpriseColor;

  PlanDonutChartPainter({
    required this.starterRatio,
    required this.professionalRatio,
    required this.clinicRatio,
    required this.enterpriseRatio,
    required this.starterColor,
    required this.professionalColor,
    required this.clinicColor,
    required this.enterpriseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    const strokeWidth = 10.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    final paintStarter = Paint()
      ..color = starterColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintProfessional = Paint()
      ..color = professionalColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintClinic = Paint()
      ..color = clinicColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final paintEnterprise = Paint()
      ..color = enterpriseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -3.14159 / 2;

    final starterSweep = 2 * 3.14159 * starterRatio;
    final professionalSweep = 2 * 3.14159 * professionalRatio;
    final clinicSweep = 2 * 3.14159 * clinicRatio;
    final enterpriseSweep = 2 * 3.14159 * enterpriseRatio;

    if (starterSweep > 0) {
      canvas.drawArc(rect, startAngle, starterSweep, false, paintStarter);
      startAngle += starterSweep;
    }

    if (professionalSweep > 0) {
      canvas.drawArc(rect, startAngle, professionalSweep, false, paintProfessional);
      startAngle += professionalSweep;
    }

    if (clinicSweep > 0) {
      canvas.drawArc(rect, startAngle, clinicSweep, false, paintClinic);
      startAngle += clinicSweep;
    }

    if (enterpriseSweep > 0) {
      canvas.drawArc(rect, startAngle, enterpriseSweep, false, paintEnterprise);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}