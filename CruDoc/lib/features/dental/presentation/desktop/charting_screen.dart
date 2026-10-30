import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dental/data/models/tooth_chart_entry_model.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/domain/dental_chart.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_2d.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/chart/tooth_chart_data.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_records.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_chart_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_screen.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_detail_view.dart';
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
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

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

/// Widths the studio steps through: below [_studio] one column (the
/// panels' contents move into the workspaces); from it the inspector sits
/// on the right; from [_studioWide] the patient pool sits on the left too.
const double _studio = 1000;
const double _studioWide = 1360;

/// Charting, laid out like an editing studio. On top: the title, the
/// patient (search to switch, allergies, history, DMFT) and recall; the
/// workspace switch (Chart, Plan, Perio, Endo, Surgery, Kids & ortho,
/// Records, Wrap-up), each with its status. Below: the patient pool (mouth
/// map, what needs care, the plan) on the left, the workspace in the
/// middle, and the inspector (visits with +, the record buttons) on the
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

class _ChartingScreenState extends ConsumerState<ChartingScreen> {
  late ChartingTab _tab = widget.initialTab;

  /// Workspaces opened so far: built once, then kept (with their state).
  late final Set<ChartingTab> _built = {widget.initialTab};

  void _go(ChartingTab tab) => setState(() {
    _tab = tab;
    _built.add(tab);
  });

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
    final records = chartRecords(context, ref, p, go: _go);
    final today = summary == null
        ? null
        : PatientActions.todaysVisit(summary, now);

    void newVisit() => PatientActions.newVisit(context, ref, p);
    void openVisit(Visit v) =>
        showVisitSessionDialog(context, visit: v, patient: p);
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
    final title = chartingTitle(context, phone: phone);
    final back = widget.picker == null
        ? CruIconButton(
            icon: CruIcons.chevronLeft,
            semanticLabel: 'Back',
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          )
        : null;

    final Widget topRow;
    if (phone) {
      topRow = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ?back,
              if (back != null) const SizedBox(width: CruSpace.s6),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?back,
                    if (back != null) const SizedBox(width: CruSpace.s8),
                    title,
                  ],
                ),
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
      );
    }

    // ---- Header row 2: workspaces, each with its status.
    final needsCare = _inOrder(
      data.teeth.where((t) => t.state == ToothState.needsCare),
    );
    final planned = _inOrder(data.teeth.where((t) => t.isPlanned));
    final planDone = items.where(DentalPlan.isDone).length;
    final kids =
        p.age < 16 ||
        findRecord(records, 'ortho')?.status != null ||
        findRecord(records, 'eruption')?.status != null;
    final tabs = [
      for (final t in ChartingTab.values)
        if (t != ChartingTab.kids || kids) t,
    ];
    ({String text, RecordTone tone})? statusOf(ChartingTab t) {
      ({String text, RecordTone tone})? from(String id) {
        final r = findRecord(records, id);
        return r?.status == null ? null : (text: r!.status!, tone: r.tone);
      }

      return switch (t) {
        ChartingTab.teeth =>
          needsCare.isNotEmpty
              ? (text: '${needsCare.length} need care', tone: RecordTone.warn)
              : data.count(ToothState.treated) > 0
              ? (
                  text: '${data.count(ToothState.treated)} treated',
                  tone: RecordTone.plain,
                )
              : null,
        ChartingTab.plan =>
          items.isEmpty
              ? null
              : (
                  text: '$planDone of ${items.length}',
                  tone: planDone == items.length
                      ? RecordTone.done
                      : RecordTone.plain,
                ),
        ChartingTab.perio => from('perio'),
        ChartingTab.rootCanals => from('endo'),
        ChartingTab.surgery => from('checklist') ?? from('sedation'),
        ChartingTab.kids =>
          from('eruption') ?? from('behaviour') ?? from('ortho'),
        ChartingTab.records => from('forms'),
        ChartingTab.wrapUp =>
          today == null
              ? null
              : today.status == VisitStatus.completed
              ? (text: "Today's visit done", tone: RecordTone.done)
              : (text: 'Visit today', tone: RecordTone.warn),
      };
    }

    final switcher = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Endo has no tab: its Clinical records button opens it.
          for (final t in tabs)
            if (t != ChartingTab.rootCanals)
              _WorkspaceTab(
                label: t.label,
                status: statusOf(t),
                selected: t == _tab,
                onTap: () => _go(t),
              ),
        ],
      ),
    );

    // ---- The panels.
    final pool = DetailsStack([
      _ToothListCard(
        title: 'Needs care',
        teeth: needsCare,
        empty: 'Nothing waiting.',
        line: (t) => t.detail(ChartLayer.dental) ?? 'Needs care',
        onOpen: (t) => showToothDetail(context, patient: p, tooth: t.number),
      ),
      _ToothListCard(
        title: 'Planned work',
        teeth: planned,
        empty: 'No work planned yet.',
        line: (t) => t.planned.join(', '),
        onOpen: (t) => showToothDetail(context, patient: p, tooth: t.number),
        trailing: CruLink(
          label: planned.isEmpty ? 'Create plan' : 'Edit plan',
          onPressed: editPlan,
        ),
      ),
    ]);
    final visitsCard = _VisitsCard(
      visits: summary?.visits ?? const <Visit>[],
      now: now,
      onOpen: openVisit,
      onNew: canBook ? newVisit : null,
    );
    final inspector = DetailsStack([
      visitsCard,
      RecordPanel(clusters: records),
    ]);
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
        final wide = box.maxWidth >= _studioWide;

        Widget workspace(ChartingTab t) => switch (t) {
          ChartingTab.teeth => scroll(
            DetailsStack([
              ToothChartCard(
                patient: p,
                fullScreen: true,
                onOpenPerio: () => _go(ChartingTab.perio),
              ),
              if (!wide) pool,
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
          ChartingTab.perio => PerioChartScreen(patient: p, embedded: true),
          ChartingTab.rootCanals => _RootCanalsTab(patient: p),
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

        // Workspaces are built when first opened, then kept, so entries,
        // layers and scroll survive a look elsewhere.
        final shown = tabs.contains(_tab) ? _tab : ChartingTab.teeth;
        final centre = IndexedStack(
          index: tabs.indexOf(shown),
          sizing: StackFit.expand,
          children: [
            for (final t in tabs)
              ExcludeFocus(
                key: ValueKey(t),
                excluding: t != shown,
                child: _built.contains(t)
                    ? workspace(t)
                    : const SizedBox.shrink(),
              ),
          ],
        );

        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topRow,
            const SizedBox(height: CruSpace.s12),
            switcher,
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
                  if (wide) ...[
                    SizedBox(width: 280, child: scroll(pool)),
                    const SizedBox(width: CruSpace.cardGap),
                  ],
                  Expanded(child: centre),
                  if (studio) ...[
                    const SizedBox(width: CruSpace.cardGap),
                    SizedBox(width: 300, child: scroll(inspector)),
                  ],
                ],
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

/// One workspace in the switch: its name and status under it; the open
/// one is raised with an accent line under it.
class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.label,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ({String text, RecordTone tone})? status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = status;
    final tone = switch (s?.tone) {
      RecordTone.warn => c.amberText,
      RecordTone.done => c.greenText,
      _ => c.label3,
    };
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: '$label${s == null ? '' : ', ${s.text}'}',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        margin: const EdgeInsets.only(right: CruSpace.s4),
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s14,
          CruSpace.s6,
          CruSpace.s14,
          CruSpace.s6,
        ),
        decoration: ShapeDecoration(
          color: selected
              ? c.surface
              : hovered
              ? c.hoverFill
              : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: (selected ? CruType.subhead.w600 : CruType.subhead.w500)
                  .tint(selected ? c.label : c.label2),
            ),
            Text(s?.text ?? ' ', style: CruType.micro.tabular.tint(tone)),
            const SizedBox(height: CruSpace.s2),
            AnimatedContainer(
              duration: CruMotion.of(context, CruMotion.fast),
              curve: CruMotion.curve,
              height: 2,
              width: selected ? 24 : 0,
              decoration: ShapeDecoration(
                color: c.accent,
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
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
  });

  /// Newest first.
  final List<Visit> visits;
  final DateTime now;
  final ValueChanged<Visit> onOpen;
  final VoidCallback? onNew;

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
  });

  final Visit visit;
  final DateTime now;
  final VoidCallback onTap;

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
          color: today
              ? c.accentTint
              : hovered
              ? c.hoverFill
              : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.iconTile),
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
            Text(VisitStatusLabel.of(status), style: CruType.caption.tint(ink)),
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

/// Two columns from this width: the chart, and the panels beside it.
const double _twoColumns = 900;

/// The chart beside its panels when wide; one scrolling column on
/// phones.
Widget _tabLayout({
  required Widget toolbar,
  required Widget main,
  required List<Widget> side,
}) => LayoutBuilder(
  builder: (context, box) {
    if (box.maxWidth < _twoColumns) {
      return SingleChildScrollView(
        child: DetailsStack([toolbar, main, ...side]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        const SizedBox(height: CruSpace.cardGap),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: main)),
              const SizedBox(width: CruSpace.cardGap),
              SizedBox(
                width: CruSize.rightColumn,
                child: SingleChildScrollView(child: DetailsStack(side)),
              ),
            ],
          ),
        ),
      ],
    );
  },
);

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
    this.trailing,
  });

  final String title;
  final List<ToothVisual> teeth;
  final String empty;
  final String Function(ToothVisual tooth) line;
  final ValueChanged<ToothVisual> onOpen;
  final Widget? trailing;

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
              trailing:
                  trailing ??
                  (teeth.isEmpty
                      ? null
                      : Text(
                          '${teeth.length}',
                          style: CruType.subhead.tabular.tint(c.label2),
                        )),
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

/// Root canals: the chart's canal layer (tap a tooth to open its root
/// canal or start one), and a card per tooth, those in progress first.
class _RootCanalsTab extends ConsumerWidget {
  const _RootCanalsTab({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final data = watchPatientChart(ref, patient.id);
    final numbering =
        ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final records =
        ref
            .watch(
              patientRecordsProvider((
                patientId: patient.id,
                kind: RecKind.endo,
              )),
            )
            .value ??
        const <DentalRecord>[];
    bool done(DentalRecord r) => r.str('status') == 'obturated';
    final ongoing = records.where((r) => !done(r)).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final finished = records.where(done).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

    void openTooth(String tooth) {
      DentalRecord? existing;
      for (final r in [...ongoing, ...finished]) {
        if (r.str('tooth') == tooth) {
          existing = r;
          break;
        }
      }
      showEndoDialog(context, patient, existing: existing, tooth: tooth);
    }

    final chart = CruCard(
      semanticLabel: 'Canals',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pulp and canals', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s2),
          Text(
            'Tap a tooth to open its root canal, or start one.',
            style: CruType.subhead.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s16),
          ToothChart2D(
            data: data,
            child: defaultMilkTeeth(data, patient),
            layer: ChartLayer.endo,
            selected: null,
            onSelect: openTooth,
            numbering: numbering,
          ),
        ],
      ),
    );

    return _tabLayout(
      toolbar: DentalTabToolbar(
        status: records.isEmpty
            ? 'No root canals yet'
            : [
                if (ongoing.isNotEmpty) '${ongoing.length} in progress',
                if (finished.isNotEmpty) '${finished.length} done',
              ].join(' · '),
        actions: [
          CruButton(
            label: 'New root canal',
            icon: CruIcons.plus,
            onPressed: () => showEndoDialog(context, patient),
          ),
        ],
      ),
      main: chart,
      side: records.isEmpty
          ? [
              CruCard(
                semanticLabel: 'Root canals',
                padding: const EdgeInsets.all(CruSpace.s24),
                child: DentalEmptyState(
                  icon: RecIcons.endo,
                  title: 'No root canals yet',
                  body:
                      'Record the diagnosis, vitality tests, each canal with '
                      'its working length, and the filling once it is done.',
                  actions: [
                    CruButton(
                      label: 'New root canal',
                      icon: CruIcons.plus,
                      kind: CruButtonKind.secondary,
                      onPressed: () => showEndoDialog(context, patient),
                    ),
                  ],
                ),
              ),
            ]
          : [
              for (final r in [...ongoing, ...finished])
                _RootCanalCard(
                  record: r,
                  state: data.of(r.str('tooth')).state,
                  numbering: numbering,
                  onTap: () => showEndoDialog(context, patient, existing: r),
                ),
            ],
    );
  }
}

/// One tooth's root canal: diagnosis, canals with working lengths, its
/// status (amber while in progress, green once filled) and dates.
class _RootCanalCard extends StatelessWidget {
  const _RootCanalCard({
    required this.record,
    required this.state,
    required this.numbering,
    required this.onTap,
  });

  final DentalRecord record;
  final ToothState state;
  final ToothNumbering numbering;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final r = record;
    final tooth = r.str('tooth');
    final done = r.str('status') == 'obturated';
    final filled = r.date('obturatedOn');
    final diagnosis = [
      if (r.str('pulpal').isNotEmpty) r.str('pulpal'),
      if (r.str('periapical').isNotEmpty) r.str('periapical'),
    ].join(' · ');
    final canals = [
      if (r.data['canals'] is List)
        for (final k in r.data['canals'] as List)
          if (k is Map && '${k['name'] ?? ''}'.isNotEmpty)
            [
              '${k['name']}',
              if (k['wl'] is num) '${(k['wl'] as num).toStringAsFixed(1)} mm',
            ].join(' '),
    ];
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: 'Root canal, ${DentalChart.name(tooth)}',
      builder: (context, hovered) => CruCard(
        semanticLabel: 'Root canal',
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tooth.isNotEmpty) ToothBadge(tooth: tooth, state: state),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tooth.isEmpty ? 'Root canal' : DentalChart.name(tooth),
                        style: CruType.callout.w600.tint(c.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (diagnosis.isNotEmpty)
                        Text(
                          diagnosis,
                          style: CruType.subhead.tint(c.label2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                CruPill(
                  text: done ? 'Filled' : 'In progress',
                  background: done ? c.greenTint : c.amberTint,
                  foreground: done ? c.greenText : c.amberText,
                ),
              ],
            ),
            if (canals.isNotEmpty) ...[
              const SizedBox(height: CruSpace.s12),
              Wrap(
                spacing: CruSpace.s6,
                runSpacing: CruSpace.s6,
                children: [
                  for (final k in canals)
                    CruPill(text: k, background: c.inset, foreground: c.label),
                ],
              ),
            ],
            const SizedBox(height: CruSpace.s10),
            Text(
              [
                'Started ${DentalFormat.date(r.recordedAt)}',
                if (filled != null) 'filled ${DentalFormat.date(filled)}',
              ].join(' · '),
              style: CruType.caption.tabular.tint(c.label3),
            ),
          ],
        ),
      ),
    );
  }
}
