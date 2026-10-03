import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/feature_usage_service.dart';
import 'package:doctor_management_app/core/utils/doctor_feature_guard.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/inventory/presentation/inventory_alert_listener.dart';
import 'package:doctor_management_app/features/mobile/mobile_backdrop.dart';
import 'package:doctor_management_app/features/mobile/mobile_home.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/mobile/mobile_nav_bar.dart';
import 'package:doctor_management_app/features/mobile/mobile_patients.dart';
import 'package:doctor_management_app/features/mobile/mobile_revenue.dart';
import 'package:doctor_management_app/features/mobile/mobile_schedule.dart';
import 'package:doctor_management_app/features/shell/components/mobile_feature_disabled_view.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The phone app: five tabs that swipe sideways, the floating ink-blue
/// nav, and (from the app root) the island at the top.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  final _pages = PageController();

  /// Created once so rebuilds don't resubscribe to Firestore.
  final Stream<List<String>> _enabledModules =
      DoctorFeatureGuard.watchEnabledModules();

  int _index = MobileTab.home;

  static const _items = [
    // Same glyphs as the desktop sidebar, so both feel like one app.
    MobileNavItem('Home', CruIcons.dashboard),
    MobileNavItem('Schedule', CruIcons.calendar),
    MobileNavItem('Patients', CruIcons.patients),
    MobileNavItem('Revenue', CruIcons.rupee),
    MobileNavItem('More', CruIcons.more),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mobileTabSwitcherProvider.notifier).state = (tab) {
        if (mounted) _goTo(tab);
      };
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int tab) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(
      tab.clamp(0, MobileTab.count - 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _tab(int index, List<String> modules) {
    final (moduleKeys, title, icon) = switch (index) {
      MobileTab.schedule => (
        const ['appointments', 'queue'],
        'Schedule',
        Icons.calendar_today_outlined,
      ),
      MobileTab.patients => (
        const ['patients'],
        'Patient Records',
        Icons.groups_rounded,
      ),
      MobileTab.revenue => (
        const ['revenue'],
        'Revenue & Financials',
        Icons.payments_outlined,
      ),
      _ => (const <String>[], '', Icons.grid_view_rounded),
    };
    final enabled =
        moduleKeys.isEmpty ||
        moduleKeys.any((k) => DoctorFeatureGuard.isEnabled(modules, k));
    if (!enabled) {
      return MobileFeatureDisabledView(
        featureTitle: title,
        icon: icon,
        onBackToDashboard: () => _goTo(MobileTab.home),
      );
    }
    return switch (index) {
      MobileTab.home => MobileHomeScreen(enabledModules: modules),
      MobileTab.schedule => const MobileScheduleScreen(),
      MobileTab.patients => const MobilePatientsScreen(),
      MobileTab.revenue => const MobileRevenueScreen(),
      _ => MobileMoreScreen(enabledModules: modules),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final waiting = ref.watch(waitingNowCountProvider);
    // Light status bar icons on a dark top (Evening, and the dark Day
    // looks), dark ones on a light Day top.
    final darkTop = c.isEvening || kMobileDayLook.darkHeader;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (darkTop ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
      // Back on another tab returns Home before it leaves the app.
      child: PopScope(
        canPop: _index == MobileTab.home,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goTo(MobileTab.home);
        },
        child: InventoryAlertListener(
          child: Scaffold(
            backgroundColor: c.canvas,
            extendBody: true,
            resizeToAvoidBottomInset: false,
            body: StreamBuilder<List<String>>(
              stream: _enabledModules,
              builder: (context, snapshot) {
                final modules =
                    snapshot.data ?? DoctorFeatureGuard.defaultModules;
                // Touches feed the Day dots (a tap's shockwave, a
                // hold's halo, a drag's trail); they only listen.
                final fx = MobileDotsFx.instance;
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: fx.down,
                  onPointerMove: fx.move,
                  onPointerUp: fx.up,
                  onPointerCancel: fx.cancel,
                  child: Stack(
                    children: [
                      Positioned.fill(child: MobileBackdrop(pages: _pages)),
                      // Content fades out as it scrolls up under the status
                      // bar, so text never runs into the clock or island.
                      ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) {
                          final top = MediaQuery.paddingOf(context).top;
                          double at(double y) =>
                              (y / rect.height).clamp(0.0, 1.0);
                          return LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: const [
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black,
                            ],
                            stops: [0, at(top - 6), at(top + 10)],
                          ).createShader(rect);
                        },
                        child: MobileTabSurface(
                          child: PageView.builder(
                            controller: _pages,
                            itemCount: MobileTab.count,
                            onPageChanged: (i) {
                              setState(() => _index = i);
                              FeatureUsageService.log(
                                const [
                                  'Home',
                                  'Schedule',
                                  'Patients',
                                  'Revenue',
                                  'More',
                                ][i],
                              );
                              ref
                                      .read(mobileCurrentTabProvider.notifier)
                                      .state =
                                  i;
                              FocusManager.instance.primaryFocus?.unfocus();
                            },
                            itemBuilder: (context, i) =>
                                MobileKeepAlive(child: _tab(i, modules)),
                          ),
                        ),
                      ),
                      Positioned(
                        left: MobileMetrics.gutter,
                        right: MobileMetrics.gutter,
                        bottom: MobileMetrics.navBottom(context),
                        child: MobileNavBar(
                          controller: _pages,
                          items: _items,
                          badges: {MobileTab.schedule: waiting},
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
