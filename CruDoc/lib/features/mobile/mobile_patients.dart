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
              child: MobileSearchField(
                controller: _search,
                hint: 'Name or phone number',
                onChanged: (q) => ref
                    .read(patientsListControllerProvider.notifier)
                    .setQuery(q),
              ),
            ),
          ),
          if (view != null && !view.firstWeek)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: MobileMetrics.gutter,
                  ),
                  children: [
                    for (final f in PatientFilter.values)
                      if (f == PatientFilter.all || (view.counts[f] ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: CruSpace.s8),
                          child: MobileChip(
                            label: f.label,
                            selected: state.filter == f,
                            attention: f.attention,
                            count: f == PatientFilter.all
                                ? null
                                : view.counts[f],
                            onTap: () => ref
                                .read(patientsListControllerProvider.notifier)
                                .setFilter(f),
                          ),
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
