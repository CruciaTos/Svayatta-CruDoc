import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_records.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_chart_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_view.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/chart_session_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/endo_dialog.dart';
import 'package:doctor_management_app/features/dental/records/perio_chart_screen.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/dental/specialties/oralmed/oralmed_history.dart';
import 'package:doctor_management_app/features/dental/specialties/publichealth/dmft.dart';
import 'package:doctor_management_app/features/files/presentation/patient_files_card.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/treatment_plan_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visit_session_dialog.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visits_card.dart';
import 'package:doctor_management_app/features/reports/presentation/certificate_dialog.dart';
import 'package:doctor_management_app/features/reports/presentation/medical_report_generation_sheet.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/scribe/presentation/prescription_generation_sheet.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/snap_column.dart';
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_top_bar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/morph_tag.dart';

export 'charting_records.dart' show ChartingTab;

/// Opens [patient]'s Charting on [tab].
Future<void> openCharting(
  BuildContext context,
  Patient patient, {
  ChartingTab tab = ChartingTab.teeth,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    builder: (_) => Theme(
      data: Theme.of(context),
      child: ChartingScreen(patient: patient, initialTab: tab),
    ),
  ),
);

/// Below this width one column (the inspector's contents move into the
/// workspaces); from it the inspector sits on the right.
const double _studio = 1000;

/// Charting, laid out like an editing studio. On top: the title, the
/// patient (search to switch, allergies, history, DMFT) and recall; the
/// workspace switch (Chart, Plan, Perio, Endo, Surgery, Kids & ortho,
/// Records, Wrap-up), each with its status. Below: the workspace, and the
/// inspector (what needs care, visits with +, the record buttons) on the
/// right. Every chairside record opens from here.
class ChartingScreen extends ConsumerStatefulWidget {
  const ChartingScreen({
    super.key,
    required this.patient,
    this.initialTab = ChartingTab.teeth,
    this.embedded = false,
    this.picker,
  });

  final Patient patient;
  final ChartingTab initialTab;

  /// Inside the sidebar's Charting page: no Scaffold or padding of its
  /// own.
  final bool embedded;

  /// The patient search beside the title (the sidebar page), in place of
  /// back.
  final Widget? picker;

  @override
  ConsumerState<ChartingScreen> createState() => _ChartingScreenState();
}

class _ChartingScreenState extends ConsumerState<ChartingScreen>
    with SingleTickerProviderStateMixin {
  /// Perio isn't a tab: opened on Perio, Charting starts on the chart and
  /// opens perio full screen.
  late ChartingTab _tab =
      widget.initialTab == ChartingTab.perio ||
          widget.initialTab == ChartingTab.rootCanals
      ? ChartingTab.teeth
      : widget.initialTab;

  /// Perio full screen, opened from the Clinical records Perio button:
  /// the button's box grows over everything under the title
  /// (design/motion-transitions.md, "Opening from a button").
  late final AnimationController _morph = AnimationController(vsync: this);

  /// Slower and softer than the usual 250 ms (asked for this one): eases
  /// in and out, so the box starts and lands gently; closing is the same
  /// path backwards.
  static const _perioMotion = Duration(milliseconds: 420);
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _morph,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: Curves.easeInOutCubicEmphasized,
  );
  late final StateController<bool> _shellFocus;

  /// Everything under the title row; perio fills it.
  final GlobalKey _area = GlobalKey(debugLabel: 'charting area');
  final GlobalKey _perioTile = GlobalKey(debugLabel: 'perio button');
  bool _perio = false;

  /// The Perio button's rectangle in [_area] when perio opened.
  Rect? _from;

  @override
  void initState() {
    super.initState();
    // Each time Charting opens it starts on the latest chart.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chartSessionProvider(widget.patient.id).notifier).state = null;
      }
    });
    _shellFocus = ref.read(shellFocusProvider.notifier);
    _morph.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    // Opened on Perio from another screen: open it full screen once the
    // Perio button is laid out, so it grows from there.
    if (widget.initialTab == ChartingTab.perio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPerio();
      });
    }
    // Opened on Endo: the chart, with the Endo dialog over it.
    if (widget.initialTab == ChartingTab.rootCanals) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showEndoDialog(context, widget.patient);
      });
    }
  }

  @override
  void dispose() {
    // Left Charting with perio open: give the sidebar back.
    if (_perio) {
      final focus = _shellFocus;
      Future.microtask(() => focus.state = false);
    }
    _t.dispose();
    _morph.dispose();
    super.dispose();
  }

  Rect? _tileRect() {
    final tile = _perioTile.currentContext?.findRenderObject();
    final area = _area.currentContext?.findRenderObject();
    if (tile is! RenderBox || area is! RenderBox || !tile.hasSize) return null;
    return tile.localToGlobal(Offset.zero, ancestor: area) & tile.size;
  }

  void _openPerio() {
    if (_perio) return;
    setState(() {
      _perio = true;
      _from = _tileRect();
    });
    // Perio is built (unseen) this frame; it and the sidebar start moving
    // together next frame, so the heavy first build doesn't eat the
    // opening frames.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_perio) return;
      _shellFocus.state = true;
      _morph.duration = CruMotion.of(context, _perioMotion);
      _morph.forward(from: 0);
    });
  }

  Future<void> _closePerio() async {
    if (!_perio || _morph.status == AnimationStatus.reverse) return;
    // Fold back while the sidebar is still collapsed, so the button is
    // where it was measured; then give the sidebar back.
    _from = _tileRect() ?? _from;
    _morph.duration = CruMotion.of(context, _perioMotion);
    await _morph.reverse();
    if (!mounted) return;
    setState(() => _perio = false);
    _shellFocus.state = false;
  }

  void _go(ChartingTab tab) {
    // Perio isn't a tab: it opens full screen.
    if (tab == ChartingTab.perio) return _openPerio();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = widget.patient;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 600;
    final now = ref.watch(dashboardNowProvider);
    final summary = ref.watch(patientSummaryProvider(p.id)).value;
    final canBook = ref.watch(clinicCanProvider(ClinicPermission.schedule));
    final canEdit = ref.watch(clinicCanProvider(ClinicPermission.clinicalEdit));
    final canBill = ref.watch(clinicCanProvider(ClinicPermission.billing));

    final omHistory = omHistoryOf(
      ref
              .watch(
                patientRecordsProvider((
                  patientId: p.id,
                  kind: RecKind.omHistory,
                )),
              )
              .value ??
          const [],
    );
    final allergies = KnownAllergies.parse(omAllergyText(omHistory));
    final entries =
        ref.watch(patientToothChartProvider(p.id)).value ??
        const <ToothChartEntryModel>[];
    final dmft = computeDmft(entries);
    final data = watchPatientChart(ref, p.id);
    final items = DentalPlan.active(
      ref.watch(patientTreatmentPlanProvider(p.id)).value ??
          const <TreatmentPlanLineItemModel>[],
    );
    final records = chartRecords(context, ref, p, go: _go, onPerio: _openPerio);
    final perioRecord = findRecord(records, 'perio');
    final today = summary == null
        ? null
        : PatientActions.todaysVisit(summary, now);

    void newVisit() => PatientActions.newVisit(context, ref, p);
    final session = watchChartSession(ref, p.id);
    final timeline = ref.watch(chartTimelineProvider(p.id));
    // A visit row loads that visit as a session; tapping the one already
    // shown (today's on Latest) opens its notes. Visits that aren't a
    // session yet (future, cancelled) open their notes too.
    void openVisit(Visit v) {
      final shown = session ?? today?.id;
      if (!timeline.isSession(v.id) || v.id == shown) {
        showVisitSessionDialog(context, visit: v, patient: p);
        return;
      }
      ref.read(chartSessionProvider(p.id).notifier).state = v.id == today?.id
          ? null
          : v.id;
    }

    Future<void> editPlan() async {
      await showTreatmentPlanDialog(context, patient: p);
      ref.invalidate(patientTreatmentPlanProvider(p.id));
    }

    // ---- Header row 1: title, patient, recall, visit.
    final pills = <Widget>[
      if (allergies != null)
        allergies.none
            ? const CruInfoPill(
                text: 'No known allergies',
                icon: CruIcons.check,
                tone: CruInfoPillTone.outlined,
              )
            : CruInfoPill(
                text: 'Allergic to ${allergies.text}',
                icon: CruIcons.warning,
                tone: CruInfoPillTone.allergy,
              ),
      if (omHistory != null)
        _Chip(
          text: omCardLine(omHistory).split(' · ').first,
          onTap: () => showOmHistoryDialog(context, p, existing: omHistory),
        ),
      if (entries.isNotEmpty)
        _Chip(
          text: p.age < 16 && dmft.primaryTotal > 0
              ? 'dmft ${dmft.primaryTotal} · DMFT ${dmft.total}'
              : 'DMFT ${dmft.total}',
        ),
    ];
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          p.fullName,
          style: CruType.callout.w600.tint(c.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          PatientFormat.ageSexLong(p),
          style: CruType.subhead.tabular.tint(c.label2),
          maxLines: 1,
        ),
      ],
    );
    // Perio full screen reads like a sub-screen of Charting: the title
    // turns from "Charting" to "Periodontal" in place (the back link above
    // turns to "‹ Charting"), the patient stays under it.
    final titleStyle = (phone ? CruType.title2 : CruType.largeTitle).tint(
      c.label,
    );
    final title = AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final turn = const Interval(0.2, 0.8).transform(_t.value);
        return Stack(
          children: [
            Opacity(
              opacity: 1 - turn,
              child: chartingTitle(context, phone: phone),
            ),
            if (_perio)
              Opacity(
                opacity: turn,
                child: Semantics(
                  header: true,
                  child: Text('Periodontal', style: titleStyle),
                ),
              ),
          ],
        );
      },
    );
    // A blue back link on top, like every sub-page: "‹ Patients" (or
    // "‹ Back" when Charting was opened as its own screen). With perio
    // open the same link reads "‹ Charting" and folds perio away; the
    // words cross-fade in place, so nothing below it moves.
    final restLabel = widget.picker == null ? 'Back' : 'Patients';
    void restBack() {
      if (widget.picker == null) {
        Navigator.of(context).maybePop();
      } else {
        ref.read(shellNavigatorProvider)?.call(DesktopTab.patients);
      }
    }

    final backLink = AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final turn = const Interval(0.2, 0.8).transform(_t.value);
        return Stack(
          children: [
            IgnorePointer(
              ignoring: _perio,
              child: Opacity(
                opacity: 1 - turn,
                child: DetailsBackLink(label: restLabel, onBack: restBack),
              ),
            ),
            if (_perio)
              Opacity(
                opacity: turn,
                child: DetailsBackLink(label: 'Charting', onBack: _closePerio),
              ),
          ],
        );
      },
    );

    final Widget topRow;
    if (phone) {
      topRow = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          backLink,
          Row(
            children: [
              title,
              const Spacer(),
              _RecallChip(patient: p),
            ],
          ),
          if (widget.picker != null) ...[
            const SizedBox(height: CruSpace.s10),
            widget.picker!,
          ],
          const SizedBox(height: CruSpace.s10),
          identity,
          const SizedBox(height: CruSpace.s8),
          Wrap(spacing: CruSpace.s6, runSpacing: CruSpace.s6, children: pills),
        ],
      );
    } else {
      // Like every page header: the title with the patient under it on
      // the left, the page's controls (search, recall) on the right.
      topRow = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                backLink,
                title,
                const SizedBox(height: CruSpace.s2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: p.fullName,
                        style: CruType.text.w600.tint(c.label),
                      ),
                      TextSpan(
                        text: '  ·  ${PatientFormat.ageSexLong(p)}',
                        style: CruType.text.tabular.tint(c.label2),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                // Pills, search and recall fade while perio is open.
                AnimatedBuilder(
                  animation: _t,
                  builder: (context, child) => Opacity(
                    opacity: 1 - const Interval(0, 0.5).transform(_t.value),
                    child: child,
                  ),
                  child: IgnorePointer(
                    ignoring: _perio,
                    child: ExcludeFocus(
                      excluding: _perio,
                      child: Row(
                        children: [
                          const SizedBox(width: CruSpace.s20),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final w in pills) ...[
                                    w,
                                    const SizedBox(width: CruSpace.s6),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: CruSpace.s12),
                          if (widget.picker != null) ...[
                            SizedBox(width: 300, child: widget.picker),
                            const SizedBox(width: CruSpace.s10),
                          ],
                          _RecallChip(patient: p),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ---- Header row 2: workspaces, each with its status.
    final needsCare = _inOrder(
      data.teeth.where((t) => t.state == ToothState.needsCare),
    );
    final kids =
        p.age < 16 ||
        findRecord(records, 'ortho')?.status != null ||
        findRecord(records, 'eruption')?.status != null;
    final tabs = [
      for (final t in ChartingTab.values)
        // Perio and Endo aren't workspaces: their buttons open them.
        if (t != ChartingTab.perio &&
            t != ChartingTab.rootCanals &&
            (t != ChartingTab.kids || kids))
          t,
    ];

    // The same switch as every other screen's sub-screens. It shrinks to
    // fit when the window is too narrow for every tab (phones), so no tab
    // is cut off, as on Patient details.
    final shownTab = tabs.contains(_tab) ? _tab : ChartingTab.teeth;
    final switcher = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: CruSegmentedControl<ChartingTab>(
        semanticLabel: 'Charting',
        segments: [for (final t in tabs) CruSegment(t, t.label)],
        selected: shownTab,
        onChanged: _go,
      ),
    );

    // ---- The panels.
    // The plan lives on the Plan tab; only what needs care sits here.
    final needsCareCard = _ToothListCard(
      title: 'Needs care',
      teeth: needsCare,
      empty: 'Nothing waiting.',
      line: (t) => t.detail(ChartLayer.dental) ?? 'Needs care',
      onOpen: (t) => showToothDetail(context, patient: p, tooth: t.number),
    );
    final visitsCard = _VisitsCard(
      visits: summary?.visits ?? const <Visit>[],
      now: now,
      viewing: session,
      onOpen: openVisit,
      onNew: canBook ? newVisit : null,
    );
    // Scrolls card by card: one always rests at the top.
    final inspector = SnapColumn(
      children: [
        needsCareCard,
        visitsCard,
        RecordPanel(clusters: records, perioKey: _perioTile),
      ],
    );
    final historyCard = _HistoryCard(
      line: omHistory == null ? null : omCardLine(omHistory),
      allergies: allergies,
      onEdit: () => showOmHistoryDialog(context, p, existing: omHistory),
    );

    DoctorLetterheadConfig letterhead() =>
        DoctorLetterheadConfig.fromProfileData(
          ref.read(doctorProfileProvider).value,
          FirebaseAuth.instance.currentUser,
        );
    void sheet(Widget child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => child,
    );

    List<ChartRecord> pick(List<String> ids) => [
      for (final id in ids) ?findRecord(records, id),
    ];

    Widget scroll(Widget child) => SingleChildScrollView(child: child);

    final studio = LayoutBuilder(
      builder: (context, box) {
        final studio = box.maxWidth >= _studio;

        Widget workspace(ChartingTab t) => switch (t) {
          ChartingTab.teeth => scroll(
            DetailsStack([
              ToothChartCard(patient: p, fullScreen: true),
              if (!studio) needsCareCard,
            ]),
          ),
          ChartingTab.plan => scroll(
            DetailsStack([
              historyCard,
              if (summary != null)
                items.isEmpty
                    ? NoPlanCard(patient: p, onCreatePlan: editPlan)
                    : TreatmentPlanCard(
                        summary: summary,
                        items: items,
                        onEditPlan: editPlan,
                        onBook: newVisit,
                      ),
              DentalProceduresCard(patient: p),
            ]),
          ),
          // Not a tab: the Perio button opens it full screen.
          ChartingTab.perio => const SizedBox.shrink(),
          // Not a workspace: the Endo button opens its dialog.
          ChartingTab.rootCanals => const SizedBox.shrink(),
          ChartingTab.surgery => scroll(
            RecordGrid(
              records: pick(['checklist', 'sedation', 'la', 'consent']),
            ),
          ),
          ChartingTab.kids => scroll(
            RecordGrid(
              records: pick(['eruption', 'behaviour', 'ortho', 'pain']),
            ),
          ),
          ChartingTab.records => scroll(
            DetailsStack([
              PatientFilesCard(
                patient: p,
                showImaging: true,
                full: true,
                visits: summary?.visits ?? const [],
              ),
              RecordGrid(records: pick(['forms', 'scan'])),
            ]),
          ),
          ChartingTab.wrapUp => scroll(
            DetailsStack([
              if (!studio) visitsCard,
              RecordGrid(
                records: [
                  if (canEdit)
                    ActionTile(
                      'Prescription',
                      CruIcons.fileText,
                      'Write and print a prescription.',
                      () => sheet(
                        PrescriptionGenerationSheet(
                          letterheadConfig: letterhead(),
                          initialPatient: p,
                        ),
                      ),
                    ).asRecord(),
                  if (canBill)
                    ActionTile(
                      'Bill',
                      CruIcons.rupee,
                      'Bill today\'s work.',
                      () => showDesktopCreateInvoiceDialog(
                        context,
                        initialPatient: p,
                      ),
                    ).asRecord(),
                  if (canBook)
                    ActionTile(
                      'Book next visit',
                      CruIcons.calendar,
                      'The next sitting, or the plan\'s next step.',
                      newVisit,
                    ).asRecord(),
                  ...pick(['recall', 'referral', 'lab']),
                  if (canEdit) ...[
                    ActionTile(
                      'Certificate',
                      RecIcons.consent,
                      'Fitness or leave certificate.',
                      () => showCertificateDialog(context, patient: p),
                    ).asRecord(),
                    ActionTile(
                      'Medical report',
                      RecIcons.form,
                      'A report for the patient or another doctor.',
                      () => sheet(
                        MedicalReportGenerationSheet(
                          letterheadConfig: letterhead(),
                          initialPatient: p,
                        ),
                      ),
                    ).asRecord(),
                  ],
                ],
              ),
            ]),
          ),
        };

        // Workspaces sit side by side and swipe like every sub-screen (the
        // header stays put). Each is built when first opened, then kept,
        // so entries, layers and scroll survive a look elsewhere.
        final shown = tabs.contains(_tab) ? _tab : ChartingTab.teeth;
        final centre = SwipePages<ChartingTab>(
          values: tabs,
          value: shown,
          onChanged: _go,
          keepAlive: true,
          builder: (context, t) =>
              ExcludeFocus(excluding: t != shown, child: workspace(t)),
        );

        // Everything under the title row: tabs, shelf, the three columns.
        final below = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switcher,
            if (session != null) ...[
              const SizedBox(height: CruSpace.s10),
              _SessionBar(
                visit: timeline.sessionOf(session)!,
                changed: timeline.changedIn(session),
                conflicts: timeline.conflictsIn(session),
                onNotes: () => showVisitSessionDialog(
                  context,
                  visit: timeline.sessionOf(session)!,
                  patient: p,
                ),
                onLatest: () =>
                    ref.read(chartSessionProvider(p.id).notifier).state = null,
              ),
            ],
            // Below the inspector's width the buttons stay on top.
            if (!studio) ...[
              const SizedBox(height: CruSpace.s10),
              RecordShelf(clusters: records),
            ],
            const SizedBox(height: CruSpace.s16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: centre),
                  if (studio) ...[
                    const SizedBox(width: CruSpace.cardGap),
                    SizedBox(width: 300, child: inspector),
                  ],
                ],
              ),
            ),
          ],
        );

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topRow,
            const SizedBox(height: CruSpace.s12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, areaBox) {
                  final area = Offset.zero & areaBox.biggest;
                  return Stack(
                    key: _area,
                    children: [
                      // The studio fades out as perio grows over it. It
                      // stays built, so scroll and workspaces survive.
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _t,
                          builder: (context, child) => Opacity(
                            opacity:
                                1 - const Interval(0, 0.5).transform(_t.value),
                            child: child,
                          ),
                          child: IgnorePointer(
                            ignoring: _perio,
                            child: ExcludeFocus(
                              excluding: _perio,
                              // Its own layer: fading it doesn't repaint
                              // the whole studio every frame.
                              child: RepaintBoundary(child: below),
                            ),
                          ),
                        ),
                      ),
                      // Perio, growing out of the Perio button.
                      if (_perio)
                        AnimatedBuilder(
                          animation: _t,
                          builder: (context, child) => MorphBox(
                            t: _t.value,
                            from: _from,
                            fromRadius: CruRadius.control,
                            area: area,
                            settled: _morph.isCompleted,
                            source: perioRecord == null
                                ? const SizedBox.shrink()
                                // Top-aligned and clipped: its row may
                                // have no status line, so the button can
                                // be shorter than this copy.
                                : UnconstrainedBox(
                                    constrainedAxis: Axis.horizontal,
                                    alignment: Alignment.topCenter,
                                    clipBehavior: Clip.hardEdge,
                                    child: RecordPanelTile(record: perioRecord),
                                  ),
                            child: child!,
                          ),
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  _closePerio,
                            },
                            // Painted once, then only scaled and faded.
                            child: RepaintBoundary(
                              child: PerioChartScreen(
                                patient: p,
                                embedded: true,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
        return body;
      },
    );
    if (widget.embedded) return studio;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Padding(
          padding: phone
              ? CruSpace.mainPaddingPhone
              : const EdgeInsets.fromLTRB(
                  CruSpace.s24,
                  CruSpace.s20,
                  CruSpace.s24,
                  CruSpace.s24,
                ),
          child: studio,
        ),
      ),
    );
  }
}

/// A quiet pill in the header (history, DMFT); pressable when [onTap].
class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final pill = CruPill(text: text, background: c.inset, foreground: c.label);
    final tap = onTap;
    if (tap == null) return pill;
    return CruPressable(
      onTap: tap,
      scaleOnPress: false,
      semanticLabel: text,
      builder: (context, hovered) => pill,
    );
  }
}

/// The next recall in the header: "Recall · 12 Apr" (overdue says so);
/// sets or changes it.
class _RecallChip extends ConsumerWidget {
  const _RecallChip({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open =
        (ref
                    .watch(
                      patientRecordsProvider((
                        patientId: patient.id,
                        kind: RecKind.recall,
                      )),
                    )
                    .value ??
                const <DentalRecord>[])
            .where((r) => recallStatusOf(r).isOpen)
            .toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final next = open.firstOrNull;
    final due = next?.recordedAt;
    final now = DateTime.now();
    final overdue =
        due != null && due.isBefore(DateTime(now.year, now.month, now.day));
    final label = due == null
        ? 'Recall'
        : '${overdue ? 'Recall overdue' : 'Recall'} · '
              '${DentalFormat.shortDate(due)}';
    return CruCapsuleButton(
      label: label,
      icon: RecIcons.recall,
      height: CruSize.control,
      semanticLabel: due == null ? 'Set a recall' : '$label, change it',
      onPressed: () =>
          showSetRecallDialog(context, patient: patient, existing: next),
    );
  }
}

/// "Charting", in the page-title style every desktop page uses.
Widget chartingTitle(BuildContext context, {bool phone = false}) => Semantics(
  header: true,
  child: Text(
    'Charting',
    style: (phone ? CruType.title2 : CruType.largeTitle).tint(
      context.cru.label,
    ),
  ),
);

/// The patient's visits in the inspector, newest first, today's lit;
/// tapping one opens it, + books a new one.
class _VisitsCard extends StatefulWidget {
  const _VisitsCard({
    required this.visits,
    required this.now,
    required this.onOpen,
    required this.onNew,
    required this.viewing,
  });

  /// Newest first.
  final List<Visit> visits;
  final DateTime now;
  final ValueChanged<Visit> onOpen;
  final VoidCallback? onNew;
  final String? viewing;

  @override
  State<_VisitsCard> createState() => _VisitsCardState();
}

class _VisitsCardState extends State<_VisitsCard> {
  static const _recent = 4;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final visits = widget.visits;
    final shown = _all ? visits : visits.take(_recent).toList();
    final more = visits.length - shown.length;
    return CruCard(
      semanticLabel: 'Visits',
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: CruSpace.s8),
                  child: Text('Visits', style: CruType.headline.tint(c.label)),
                ),
              ),
              if (widget.onNew != null)
                CruIconButton(
                  icon: CruIcons.plus,
                  semanticLabel: 'New visit',
                  tooltip: 'New visit',
                  onPressed: widget.onNew,
                ),
            ],
          ),
          const SizedBox(height: CruSpace.s4),
          if (visits.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: CruSpace.s8),
              child: Text(
                'No visits yet.',
                style: CruType.subhead.tint(c.label2),
              ),
            )
          else ...[
            for (final v in shown)
              _VisitRow(
                visit: v,
                now: widget.now,
                viewing: v.id == widget.viewing,
                onTap: () => widget.onOpen(v),
              ),
            if (more > 0 || _all && visits.length > _recent)
              Padding(
                padding: const EdgeInsets.only(
                  top: CruSpace.s4,
                  left: CruSpace.s8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CruLink(
                    label: _all ? 'Show fewer' : 'Show $more more',
                    onPressed: () => setState(() => _all = !_all),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({
    required this.visit,
    required this.now,
    required this.onTap,
    required this.viewing,
  });

  final Visit visit;
  final DateTime now;
  final VoidCallback onTap;
  final bool viewing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final t = visit.scheduledStart;
    final today = DateUtils.isSameDay(t, now);
    final status = PatientsBuilder.visitStatus(visit, now);
    final ink = switch (status) {
      VisitRowStatus.done => c.greenText,
      VisitRowStatus.notRecorded => c.amberText,
      _ => c.label2,
    };
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: 'Open the visit on ${PatientFormat.weekdayDate(t)}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s8,
          vertical: CruSpace.s6,
        ),
        decoration: ShapeDecoration(
          color: viewing
              ? c.inset
              : today
              ? c.accentTint
              : hovered
              ? c.hoverFill
              : c.hoverFill.withValues(alpha: 0),
          // The visit loaded as a session gets a blue ring (clear on the
          // rest, so rows don't shift).
          shape: cruShape(
            CruRadius.iconTile,
            side: BorderSide(
              color: viewing ? c.accent : c.accent.withValues(alpha: 0),
              width: 1.5,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                today ? 'Today' : DentalFormat.shortDate(t),
                style: CruType.subhead.w600.tabular.tint(
                  today ? c.accentText : c.label,
                ),
              ),
            ),
            Expanded(
              child: Text(
                visitTitle(visit),
                style: CruType.subhead.tint(c.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: CruSpace.s6),
            Text(
              viewing ? 'Viewing' : VisitStatusLabel.of(status),
              style: viewing
                  ? CruType.caption.w600.tint(c.label)
                  : CruType.caption.tint(ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Done", "Booked", "Not recorded"… for a visit row status.
abstract final class VisitStatusLabel {
  static String of(VisitRowStatus s) => switch (s) {
    VisitRowStatus.booked => 'Booked',
    VisitRowStatus.done => 'Done',
    VisitRowStatus.notRecorded => 'Not recorded',
    VisitRowStatus.cancelled => 'Cancelled',
    VisitRowStatus.missed => 'Missed',
  };
}

/// Medical history in the inspector: allergies and the oral medicine
/// line, with Edit.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.line,
    required this.allergies,
    required this.onEdit,
  });

  final String? line;
  final KnownAllergies? allergies;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final a = allergies;
    return CruCard(
      semanticLabel: 'Medical history',
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailsCardHeader(
            title: 'Medical history',
            trailing: CruLink(
              label: line == null ? 'Add' : 'Edit',
              onPressed: onEdit,
            ),
          ),
          const SizedBox(height: CruSpace.s8),
          Text(
            a == null
                ? 'Allergies not recorded'
                : a.none
                ? 'No known allergies'
                : 'Allergic to ${a.text}',
            style: CruType.subhead.tint(
              a != null && !a.none ? c.redText : c.label2,
            ),
          ),
          if (line != null) ...[
            const SizedBox(height: CruSpace.s4),
            Text(line!, style: CruType.subhead.tint(c.label)),
          ],
        ],
      ),
    );
  }
}

/// Teeth in chart order (upper right to lower right, then milk teeth).
final Map<String, int> _chartOrder = {
  for (final (i, t) in [
    ...DentalChart.adultUpper,
    ...DentalChart.adultLower,
    ...DentalChart.childUpper,
    ...DentalChart.childLower,
  ].indexed)
    t: i,
};

List<ToothVisual> _inOrder(Iterable<ToothVisual> teeth) => teeth.toList()
  ..sort(
    (a, b) =>
        (_chartOrder[a.number] ?? 99).compareTo(_chartOrder[b.number] ?? 99),
  );

/// A list of teeth: badge, name and one line; each opens the tooth.
class _ToothListCard extends StatelessWidget {
  const _ToothListCard({
    required this.title,
    required this.teeth,
    required this.empty,
    required this.line,
    required this.onOpen,
  });

  final String title;
  final List<ToothVisual> teeth;
  final String empty;
  final String Function(ToothVisual tooth) line;
  final ValueChanged<ToothVisual> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: title,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: DetailsCardHeader(
              title: title,
              trailing: teeth.isEmpty
                  ? null
                  : Text(
                      '${teeth.length}',
                      style: CruType.subhead.tabular.tint(c.label2),
                    ),
            ),
          ),
          if (teeth.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(empty, style: CruType.subhead.tint(c.label2)),
            ),
          for (var i = 0; i < teeth.length; i++) ...[
            if (i > 0)
              const CruSeparator(
                indent: CruSpace.s12 + CruSize.iconTile + CruSpace.s12,
                endIndent: CruSpace.s12,
              ),
            _ToothRow(
              tooth: teeth[i],
              line: line(teeth[i]),
              onTap: () => onOpen(teeth[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToothRow extends StatelessWidget {
  const _ToothRow({
    required this.tooth,
    required this.line,
    required this.onTap,
  });

  final ToothVisual tooth;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: '${DentalChart.name(tooth.number)}: $line',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Row(
          children: [
            ToothBadge(tooth: tooth.number, state: tooth.state),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DentalChart.name(tooth.number),
                    style: CruType.callout.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    line,
                    style: CruType.subhead.tint(c.label2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
          ],
        ),
      ),
    );
  }
}

/// Above the workspaces while an older visit is loaded: which visit, what
/// it changed, any conflicts, and the way back to the latest chart.
class _SessionBar extends StatelessWidget {
  const _SessionBar({
    required this.visit,
    required this.changed,
    required this.conflicts,
    required this.onNotes,
    required this.onLatest,
  });

  final Visit visit;
  final Set<String> changed;
  final Set<String> conflicts;
  final VoidCallback onNotes;
  final VoidCallback onLatest;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    String teeth(Set<String> s) => (s.toList()..sort()).join(', ');
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s16,
        CruSpace.s12,
        CruSpace.s12,
        CruSpace.s12,
      ),
      decoration: ShapeDecoration(
        color: c.inset,
        shape: cruShape(CruRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Viewing the ${DentalFormat.shortDate(visit.scheduledStart)} '
                  'visit · ${visitTitle(visit)}',
                  style: CruType.callout.w600.tint(c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  changed.isEmpty
                      ? 'No changes in this visit yet. Changes made here carry '
                            'forward to later visits, except on teeth they changed.'
                      : 'Changed here: ${teeth(changed)}. Changes carry forward '
                            'to later visits, except on teeth they changed.',
                  style: CruType.subhead.tint(c.label2),
                ),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    'An earlier visit changed ${teeth(conflicts)} after this '
                    'visit did. Save the tooth again here to keep it as it is.',
                    style: CruType.subhead.tint(c.amberText),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruButton(
            label: 'Visit notes',
            kind: CruButtonKind.secondary,
            onPressed: onNotes,
          ),
          const SizedBox(width: CruSpace.s8),
          CruButton(
            label: 'Back to latest',
            kind: CruButtonKind.secondary,
            onPressed: onLatest,
          ),
        ],
      ),
    );
  }
}
