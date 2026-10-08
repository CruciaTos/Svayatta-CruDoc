import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/mobile/mobile_backdrop.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patients: search, the same filters as the desktop, and one row per
/// patient. Tap opens the record; hold for call, WhatsApp, book or pay.
class MobilePatientsScreen extends ConsumerStatefulWidget {
  const MobilePatientsScreen({super.key});

  @override
  ConsumerState<MobilePatientsScreen> createState() =>
      _MobilePatientsScreenState();
}

class _MobilePatientsScreenState extends ConsumerState<MobilePatientsScreen> {
  late final _search = TextEditingController(
    text: ref.read(patientsListControllerProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n, PatientsListView view) {
    // Reveal the next page before the end comes into view.
    if (n.metrics.extentAfter < 600 && view.visible.length < view.rows.length) {
      ref.read(patientsListControllerProvider.notifier).showMore();
    }
    return false;
  }

  void _sheet(PatientSummary s) {
    final p = s.patient;
    final hasPhone = p.phone.trim().isNotEmpty;
    showMobileActionSheet(
      context,
      title: s.name,
      subtitle: [
        PatientFormat.ageSex(p),
        if (hasPhone) PatientFormat.phone(p.phone),
      ].where((t) => t.isNotEmpty).join(' · '),
      leading: MobileAvatar(name: s.name, size: 34),
      actions: [
        if (hasPhone) ...[
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
        MobileSheetAction(
          label: 'Book a visit',
          icon: CruIcons.calendar,
          tone: MobileTone.blue,
          onTap: () => PatientActions.newVisit(mobileRoot(context), ref, p),
        ),
        if (s.hasBalance)
          MobileSheetAction(
            label: 'Record payment',
            detail: '${PatientFormat.rupees(s.balance)} due',
            icon: CruIcons.rupee,
            tone: MobileTone.green,
            onTap: () =>
                PatientActions.recordPayment(mobileRoot(context), ref, s),
          ),
        MobileSheetAction(
          label: 'Open record',
          icon: CruIcons.fileText,
          tone: MobileTone.sky,
          onTap: () => openMobilePatient(context, p),
        ),
      ],
    );
  }

  void _openFilterSheet(
    PatientsListState state,
    PatientsListView? view,
  ) {
    final root = mobileRoot(context);
    showModalBottomSheet<void>(
      context: root,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (sheetContext) {
        final c = sheetContext.cru;
        return Consumer(
          builder: (context, ref, _) {
            final currentState = ref.watch(patientsListControllerProvider);
            final currentView = ref.watch(patientsListViewProvider).value;
            final counts = currentView?.counts ?? const {};

            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  CruSpace.s8,
                  0,
                  CruSpace.s8,
                  CruSpace.s8,
                ),
                decoration: ShapeDecoration(
                  color: c.surface,
                  shape: cruShape(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: CruSpace.s8),
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: ShapeDecoration(
                          color: c.track,
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Filter Patients',
                                style: MobileType.headline.tint(c.label),
                              ),
                              const SizedBox(height: CruSpace.s2),
                              Text(
                                'Narrow down patient list',
                                style: MobileType.subhead.tint(c.label2),
                              ),
                            ],
                          ),
                          if (currentState.filter != PatientFilter.all)
                            CruPressable(
                              onTap: () {
                                ref
                                    .read(patientsListControllerProvider.notifier)
                                    .setFilter(PatientFilter.all);
                              },
                              semanticLabel: 'Reset filters',
                              builder: (context, _) => Text(
                                'Reset',
                                style: MobileType.callout.w600.tint(c.accentText),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const CruSeparator(),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CruSpace.s12,
                          vertical: CruSpace.s8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: Text(
                                'FILTERS',
                                style: MobileType.caption.w600.tint(c.label3),
                              ),
                            ),
                            for (final f in PatientFilter.values)
                              if (f == PatientFilter.all || (counts[f] ?? 0) > 0)
                                CruPressable(
                                  onTap: () {
                                    ref
                                        .read(patientsListControllerProvider.notifier)
                                        .setFilter(f);
                                    Navigator.of(sheetContext).pop();
                                  },
                                  semanticLabel: f.label,
                                  builder: (context, hovered) {
                                    final isSelected = currentState.filter == f;
                                    final count = f == PatientFilter.all
                                        ? currentView?.total
                                        : counts[f];
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: CruSpace.s12,
                                        vertical: CruSpace.s12,
                                      ),
                                      decoration: ShapeDecoration(
                                        color: isSelected
                                            ? c.accentTint
                                            : (hovered ? c.hoverFill : c.surface),
                                        shape: cruShape(CruRadius.control),
                                      ),
                                      child: Row(
                                        children: [
                                          if (f.attention) ...[
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: c.amberText,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: CruSpace.s8),
                                          ],
                                          Expanded(
                                            child: Text(
                                              f.label,
                                              style: (isSelected
                                                      ? MobileType.row.w600
                                                      : MobileType.row)
                                                  .tint(
                                                    isSelected
                                                        ? c.accentText
                                                        : c.label,
                                                  ),
                                            ),
                                          ),
                                          if (count != null) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: ShapeDecoration(
                                                color: isSelected
                                                    ? c.accent.withValues(alpha: 0.15)
                                                    : c.inset,
                                                shape: const StadiumBorder(),
                                              ),
                                              child: Text(
                                                '$count',
                                                style: MobileType.caption.tabular.tint(
                                                  isSelected
                                                      ? c.accentText
                                                      : c.label2,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: CruSpace.s8),
                                          ],
                                          if (isSelected)
                                            CruIcon(
                                              CruIcons.check,
                                              size: 18,
                                              strokeWidth: 2.2,
                                              color: c.accentText,
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            const SizedBox(height: CruSpace.s12),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: Text(
                                'SORT BY',
                                style: MobileType.caption.w600.tint(c.label3),
                              ),
                            ),
                            for (final s in PatientSort.values)
                              CruPressable(
                                onTap: () {
                                  ref
                                      .read(patientsListControllerProvider.notifier)
                                      .setSort(s);
                                  Navigator.of(sheetContext).pop();
                                },
                                semanticLabel: s.label,
                                builder: (context, hovered) {
                                  final isSelected = currentState.sort == s;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: CruSpace.s12,
                                      vertical: CruSpace.s12,
                                    ),
                                    decoration: ShapeDecoration(
                                      color: isSelected
                                          ? c.accentTint
                                          : (hovered ? c.hoverFill : c.surface),
                                      shape: cruShape(CruRadius.control),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s.label,
                                            style: (isSelected
                                                    ? MobileType.row.w600
                                                    : MobileType.row)
                                                .tint(
                                                  isSelected
                                                      ? c.accentText
                                                      : c.label,
                                                ),
                                          ),
                                        ),
                                        if (isSelected)
                                          CruIcon(
                                            CruIcons.check,
                                            size: 18,
                                            strokeWidth: 2.2,
                                            color: c.accentText,
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: CruSpace.s8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientsListControllerProvider);
    final async = ref.watch(patientsListViewProvider);
    final now = ref.watch(dashboardNowProvider);
    final view = async.value;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) => view == null ? false : _onScroll(n, view),
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: MobileHeader(
              title: 'Patients',
              subtitle: view == null
                  ? null
                  : PatientFormat.headerLine(view.total, view.newThisMonth),
              trailing: MobileCircleButton(
                icon: CruIcons.userPlus,
                semanticLabel: 'Add patient',
                onPressed: () => DashboardActions.addPatient(context),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileMetrics.gutter,
                CruSpace.s16,
                MobileMetrics.gutter,
                CruSpace.s12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: MobileSearchField(
                      controller: _search,
                      hint: 'Name or phone number',
                      onChanged: (q) => ref
                          .read(patientsListControllerProvider.notifier)
                          .setQuery(q),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  _MobileFilterButton(
                    selectedFilter: state.filter,
                    onTap: () => _openFilterSheet(state, view),
                  ),
                ],
              ),
            ),
          ),

          if (view?.balanceStrip case final b?)
            _strip(
              context,
              '${PatientFormat.rupees(b.total)} outstanding · '
              '${b.patients} ${b.patients == 1 ? 'patient' : 'patients'}',
            ),
          if (view?.followUpStrip case final f?)
            _strip(
              context,
              '${f.patients} ${f.patients == 1 ? 'patient' : 'patients'} · '
              'longest overdue ${PatientFormat.days(f.longestDays)}',
            ),
          ...switch (async) {
            AsyncData(:final value) when value.total == 0 => [
              SliverToBoxAdapter(
                child: MobileEmpty(
                  icon: CruIcons.patients,
                  title: 'No patients yet',
                  body: 'Add your first patient to start their record.',
                  action: 'Add patient',
                  onAction: () => DashboardActions.addPatient(context),
                ),
              ),
            ],
            AsyncData(:final value) when value.rows.isEmpty => [
              SliverToBoxAdapter(
                child: MobileEmpty(
                  icon: CruIcons.search,
                  title: 'No matches',
                  body: state.query.isEmpty
                      ? 'No one fits this filter right now.'
                      : 'No patient matches "${state.query}".',
                ),
              ),
            ],
            AsyncData(:final value) => [
              const SliverToBoxAdapter(child: SizedBox(height: CruSpace.s16)),
              for (final (i, g) in value.groups.indexed) ...[
                if (i > 0)
                  const SliverToBoxAdapter(
                    child: SizedBox(height: CruSpace.s12),
                  ),
                SliverToBoxAdapter(
                  child: MobileRowGroup(
                    title: g.title,
                    children: [
                      for (final s in g.rows)
                        _PatientRow(
                          summary: s,
                          now: now,
                          onTap: () => openMobilePatient(context, s.patient),
                          onLongPress: () => _sheet(s),
                        ),
                    ],
                  ),
                ),
              ],
              if (value.visible.length < value.rows.length)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(CruSpace.s16),
                    child: Center(
                      child: Text(
                        'Showing ${value.visible.length} of ${value.rows.length}',
                        style: MobileType.caption.tint(
                          // On the Day cobalt field, light; else as before.
                          !context.cru.isEvening &&
                                  kMobileDayLook == MobileDayLook.cobalt
                              ? Colors.white.withValues(alpha: 0.7)
                              : context.cru.label3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            AsyncError(:final error) => [
              SliverToBoxAdapter(
                child: MobileEmpty(
                  icon: CruIcons.warning,
                  title: 'Could not load patients',
                  body: '$error',
                ),
              ),
            ],
            _ => [
              const SliverToBoxAdapter(child: SizedBox(height: CruSpace.s16)),
              const SliverToBoxAdapter(
                child: MobileRowGroup(
                  children: [MobileLoading('Loading patients…', height: 160)],
                ),
              ),
            ],
          },
          SliverToBoxAdapter(
            child: SizedBox(height: MobileMetrics.bottom(context)),
          ),
        ],
      ),
    );
  }

  Widget _strip(BuildContext context, String text) {
    final (bg, fg) = mobileTone(context.cru, MobileTone.amber);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MobileMetrics.gutter,
          CruSpace.s12,
          MobileMetrics.gutter,
          0,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CruSpace.s14,
            vertical: CruSpace.s10,
          ),
          decoration: ShapeDecoration(
            color: bg,
            shape: cruShape(CruRadius.control),
          ),
          child: Text(text, style: MobileType.subhead.w600.tabular.tint(fg)),
        ),
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.summary,
    required this.now,
    required this.onTap,
    required this.onLongPress,
  });

  final PatientSummary summary;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = summary;
    final last = s.lastVisit;
    final next = s.nextVisit;
    String? seen;
    if (last != null) {
      final d = PatientFormat.day(last.scheduledStart, now);
      seen = d == 'Today' || d == 'Yesterday'
          ? 'Seen ${d.toLowerCase()}'
          : 'Last seen $d';
    }
    final sub = [
      PatientFormat.ageSex(s.patient),
      seen ?? s.condition ?? '',
    ].where((t) => t.isNotEmpty).join(' · ');

    Widget? trailing;
    if (s.hasBalance) {
      trailing = Text(
        PatientFormat.rupees(s.balance),
        style: MobileType.subhead.w600.tabular.tint(
          mobileTone(c, MobileTone.amber).$2,
        ),
      );
    } else if (s.followUpOverdue) {
      trailing = const MobilePill('Overdue', tone: MobileTone.amber);
    } else if (next != null) {
      trailing = MobilePill(
        PatientFormat.day(next.scheduledStart, now),
        tone: MobileTone.blue,
        icon: CruIcons.calendar,
      );
    }

    return MobileRow(
      leading: MobileAvatar(name: s.name, size: 34),
      title: s.name,
      subtitle: sub.isEmpty ? null : sub,
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _MobileFilterButton extends StatelessWidget {
  const _MobileFilterButton({
    required this.selectedFilter,
    required this.onTap,
  });

  final PatientFilter selectedFilter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final isActive = selectedFilter != PatientFilter.all;

    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Filter patients',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: 48,
        width: 48,
        decoration: ShapeDecoration(
          color: isActive
              ? c.accentTint
              : (hovered ? c.hoverFill : c.surface),
          shape: cruShape(
            CruRadius.control + 2,
            side: BorderSide(
              color: isActive
                  ? c.accent.withValues(alpha: 0.35)
                  : c.hairline,
            ),
          ),
          shadows: [
            BoxShadow(
              color: const Color(0xFF0B1B4D).withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CruIcon(
              CruIcons.settings,
              size: 20,
              strokeWidth: 2,
              color: isActive ? c.accentText : c.label2,
            ),
            if (isActive)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
