import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/services/access_audit_service.dart';
import 'package:doctor_management_app/features/dental/specialties/oralmed/oralmed_history.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_chart_card.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_card.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/homeopathy_patient_details_screen.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_top_bar.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/identity_header.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/medical_history_card.dart';
import 'package:doctor_management_app/shared/widgets/morph_tag.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/payments_block.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/session_history_card.dart';
import 'package:doctor_management_app/features/scribe/data/models/consultation_note.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/treatment_plan_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visit_session_dialog.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visits_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/assigned_doctors_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/physio_photos_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/muscle_chart_card.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/files/presentation/patient_files_card.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/revenue/presentation/desktop_create_invoice_dialog.dart';
import 'package:doctor_management_app/features/scribe/presentation/prescription_generation_sheet.dart';
import 'package:doctor_management_app/features/reports/presentation/medical_report_generation_sheet.dart';
import 'package:doctor_management_app/features/reports/presentation/certificate_dialog.dart';

/// Main-area padding for Patient details (the dashboard's, 24 on top).
final EdgeInsets _padding = CruSpace.mainPadding.copyWith(top: CruSpace.s24);

/// Phones: even 16 px sides (the desktop's padding is lopsided for the
/// sidebar), 8 on top under the safe area.
const EdgeInsets _phonePadding = EdgeInsets.fromLTRB(16, 8, 16, 32);

/// Narrower than this, Patient details uses [_phonePadding].
const double _phoneWidth = PatientDetailsHeader.phoneBelow;

/// Patient details content (no Scaffold): a pinned header (the patient
/// and their actions, with the Overview / Clinical switch) over those two
/// pages. Overview's Visits, Files and Payments cards open sub-screens.
///
/// Every visit number comes from `patientSummaryProvider`, the same
/// summary the Patients list and preview pane read.
class PatientDetailsView extends ConsumerWidget {
  const PatientDetailsView({
    super.key,
    required this.patientId,
    required this.onBack,
  });

  final String patientId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Deduplicated by the service, so rebuilds don't add log entries.
    AccessAuditService.instance.patientViewed(patientId);
    final summary = ref.watch(patientSummaryProvider(patientId));
    return summary.when(
      loading: () => _DetailsSkeleton(onBack: onBack),
      error: (_, _) => _Missing(
        onBack: onBack,
        message: "This patient couldn't be loaded. Try again in a moment.",
      ),
      data: (s) => s == null
          ? _Missing(
              onBack: onBack,
              message: "This patient isn't in your records any more.",
            )
          : _DetailsBody(summary: s, onBack: onBack),
    );
  }
}

/// Patient details as a pushed route (canvas background). Follows Day /
/// Evening like the shell: routes sit under the app's Day theme otherwise.
class PatientDetailsScreen extends ConsumerWidget {
  const PatientDetailsScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: CruTheme.of(ref.watch(resolvedAppearanceProvider)),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: PatientDetailsView(
              patientId: patientId,
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pages the header's switch moves between (they slide sideways).
enum _Tab {
  overview('Overview'),
  clinical('Clinical');

  const _Tab(this.label);
  final String label;
}

/// Patient details' sub-screens, each opened from its Overview card.
enum _Sub {
  visits('Visits'),
  files('Files'),
  payments('Payments');

  const _Sub(this.label);
  final String label;
}

class _DetailsBody extends ConsumerStatefulWidget {
  const _DetailsBody({required this.summary, required this.onBack});

  final PatientSummary summary;
  final VoidCallback onBack;

  @override
  ConsumerState<_DetailsBody> createState() => _DetailsBodyState();
}

/// Overview and Clinical are pages under the header's switch. A
/// sub-screen (Visits, Files, Payments) opens as the same box: its card
/// grows on all four sides to the area under the header while the card's
/// contents fade out and the sub-screen (scaled with the box) fades in.
/// Back folds it into the card again. Elements both show (visit and file
/// rows, the title) move from the card's place to the sub-screen's
/// instead of fading ([MorphTag]). See design/motion-transitions.md.
class _DetailsBodyState extends ConsumerState<_DetailsBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(vsync: this);
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _morph,
    curve: CruMotion.curve,
    reverseCurve: CruMotion.curve.flipped,
  );

  /// The area under the header, which the sub-screens fill.
  final GlobalKey _area = GlobalKey();
  final Map<_Sub, GlobalKey> _cards = {
    for (final s in _Sub.values) s: GlobalKey(debugLabel: '${s.name} card'),
  };

  _Tab _tab = _Tab.overview;
  _Sub? _open;

  /// The card's rectangle in [_area] when it opened.
  Rect? _from;

  /// Elements both the card and its sub-screen show, and their trips.
  final MorphRegistry _registry = MorphRegistry();
  List<MorphFlight> _flights = const [];

  /// The open sub-screen's root, as it lies at rest.
  final GlobalKey _page = GlobalKey(debugLabel: 'sub-screen');

  @override
  void initState() {
    super.initState();
    // Open, settled, folding, closed: what is hidden and what flies.
    _morph.addStatusListener((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t.dispose();
    _morph.dispose();
    super.dispose();
  }

  Rect? _cardRect(_Sub sub) {
    final card = _cards[sub]!.currentContext?.findRenderObject();
    final area = _area.currentContext?.findRenderObject();
    if (card is! RenderBox || area is! RenderBox || !card.hasSize) return null;
    return card.localToGlobal(Offset.zero, ancestor: area) & card.size;
  }

  /// Where each shared element is in the card and in the sub-screen.
  List<MorphFlight> _measure(_Sub sub) {
    final card = _cards[sub]!.currentContext?.findRenderObject();
    final page = _page.currentContext?.findRenderObject();
    final area = _area.currentContext?.findRenderObject();
    final from = _from;
    if (card is! RenderBox ||
        page is! RenderBox ||
        area is! RenderBox ||
        from == null) {
      return const [];
    }
    return measureMorphFlights(
      registry: _registry,
      group: sub.name,
      sourceRoot: card,
      sourceOrigin: from.topLeft,
      destinationRoot: page,
      area: Offset.zero & area.size,
    );
  }

  void _openSub(_Sub sub) {
    if (_open != null) return;
    setState(() {
      _open = sub;
      _from = _cardRect(sub);
      _flights = const [];
    });
    // The sub-screen is laid out (unseen) first, so its elements can be
    // measured before anything moves.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _open != sub) return;
      setState(() => _flights = _measure(sub));
      _morph.duration = CruMotion.of(context);
      _morph.forward(from: 0);
    });
  }

  Future<void> _close() async {
    final sub = _open;
    if (sub == null || _morph.status == AnimationStatus.reverse) return;
    // Overview kept its scroll, so the card is where it was; the
    // sub-screen may have scrolled, so measure again.
    _from = _cardRect(sub) ?? _from;
    setState(() => _flights = _measure(sub));
    _morph.duration = CruMotion.of(context);
    await _morph.reverse();
    if (mounted) {
      setState(() {
        _open = null;
        _flights = const [];
      });
    }
  }

  /// The switch: a sub-screen open over Overview folds first.
  void _go(_Tab tab) {
    if (_open != null) _close();
    if (tab != _tab) setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final s = widget.summary;
    final p = s.patient;
    final now = ref.watch(dashboardNowProvider);
    final specialty = ref.watch(activeDoctorSpecialtyProvider).value?.type;
    // Clinical parts are for people whose role includes clinical records.
    final clinical = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalView),
    );
    final isDentist = clinical && ref.watch(isDentistProvider);
    final canEdit = ref.watch(clinicCanProvider(ClinicPermission.patientsEdit));
    final canBook = ref.watch(clinicCanProvider(ClinicPermission.schedule));
    final canClinicalEdit = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalEdit),
    );
    final canBill = ref.watch(clinicCanProvider(ClinicPermission.billing));
    final isPhysio = clinical && ref.watch(isPhysiotherapyProvider);
    final isHomeopath = clinical && specialty == DoctorSpecialtyType.homeopathy;
    // Imaging studies show with the files: one place for everything filed
    // to the patient.
    final showImaging = ref.watch(hasDentalRadiologyProvider);
    final hasClinical = isDentist || isPhysio || isHomeopath;
    final hasFiles = clinical || showImaging;

    // Dental plan (dentists only). Declined items are dropped.
    final items = isDentist
        ? DentalPlan.active(
            ref.watch(patientTreatmentPlanProvider(s.id)).value ??
                const <TreatmentPlanLineItemModel>[],
          )
        : const <TreatmentPlanLineItemModel>[];
    // Homeopathy case sheet (homeopaths only): allergies and history.
    final caseSheet = isHomeopath
        ? ref.watch(homeopathyCaseSheetProvider(s.id)).value
        : null;
    // Dentists: allergies from the oral medicine history.
    final omHistory = isDentist
        ? omHistoryOf(
            ref
                    .watch(
                      patientRecordsProvider((
                        patientId: s.id,
                        kind: RecKind.omHistory,
                      )),
                    )
                    .value ??
                const [],
          )
        : null;
    final allergies = KnownAllergies.parse(
      isHomeopath
          ? caseSheet?.medicalHistory.allergies
          : omAllergyText(omHistory),
    );

    void newVisit() => PatientActions.newVisit(context, ref, p);
    void edit() => PatientActions.edit(context, ref, p);
    void recordPayment() => PatientActions.recordPayment(context, ref, s);
    void newBill() => showDesktopCreateInvoiceDialog(context, initialPatient: p);
    void openVisit(Visit v) =>
        showVisitSessionDialog(context, visit: v, patient: p);
    Future<void> editPlan() async {
      await showTreatmentPlanDialog(context, patient: p);
      if (context.mounted) ref.invalidate(patientTreatmentPlanProvider(s.id));
    }

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

    final menu = DetailsMoreMenu(
      patientName: p.fullName,
      create: [
        if (canBill) (label: 'New bill', onPressed: newBill),
        if (canClinicalEdit) ...[
          (
            label: 'Prescription',
            onPressed: () => sheet(
              PrescriptionGenerationSheet(
                letterheadConfig: letterhead(),
                initialPatient: p,
              ),
            ),
          ),
          (
            label: 'Medical report',
            onPressed: () => sheet(
              MedicalReportGenerationSheet(
                letterheadConfig: letterhead(),
                initialPatient: p,
              ),
            ),
          ),
          (
            label: 'Medical certificate',
            onPressed: () => showCertificateDialog(context, patient: p),
          ),
        ],
      ],
      manage: [
        if (canEdit) ...[
          (label: 'Edit details', onPressed: edit),
          (
            label: 'Delete patient',
            onPressed: () async {
              final deleted = await PatientActions.delete(context, ref, p);
              if (deleted) widget.onBack();
            },
          ),
        ],
      ],
    );

    // Who treats this patient. Hides itself unless the clinic scopes its
    // doctors to the patients they treat.
    final assignedDoctors =
        ref.watch(clinicAccessProvider).value?.clinicalAccessScope == 'assigned'
        ? AssignedDoctorsCard(
            patientId: s.id,
            assignedDoctorUids: p.assignedDoctorUids,
          )
        : null;
    // Scribe notes open from their visit. Only notes whose visit isn't in
    // the list (removed, or from another device's queue) keep a card.
    final visitIds = {for (final v in s.visits) v.id};
    final orphanSessions = clinical
        ? <ConsultationNote>[
            for (final n
                in ref.watch(sessionHistoryProvider(s.id)).value ?? const [])
              if (!visitIds.contains(n.visitId)) n,
          ]
        : const <ConsultationNote>[];

    // The Overview cards that open a sub-screen.
    final sources = <_Sub, Widget>{
      _Sub.visits: VisitsCard(
        summary: s,
        now: now,
        showClinical: clinical,
        onOpen: openVisit,
        onSeeAll: () => _openSub(_Sub.visits),
      ),
      if (hasFiles)
        _Sub.files: PatientFilesCard(
          patient: p,
          showImaging: showImaging,
          onSeeAll: () => _openSub(_Sub.files),
        ),
      _Sub.payments: PaymentsSummaryCard(
        summary: s,
        onRecordPayment: recordPayment,
        onSeeAll: () => _openSub(_Sub.payments),
        showBills: canBill,
      ),
    };
    final open = sources.containsKey(_open) ? _open : null;
    final tabs = [_Tab.overview, if (hasClinical) _Tab.clinical];
    final tab = tabs.contains(_tab) ? _tab : _Tab.overview;

    return PopScope(
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final phone = constraints.maxWidth < _phoneWidth;
          final padding = phone ? _phonePadding : _padding;
          final wide =
              constraints.maxWidth - padding.horizontal >=
              CruBreakpoint.detailsTwoColumn;

          // A source card in place on Overview. It hides while it is the
          // box, which stands in its place.
          Widget? card(_Sub sub) {
            final w = sources[sub];
            if (w == null) return null;
            return KeyedSubtree(
              key: _cards[sub],
              child: MorphScope(
                side: MorphSide.source,
                group: sub.name,
                registry: _registry,
                child: Opacity(opacity: open == sub ? 0 : 1, child: w),
              ),
            );
          }

          final history = clinical
              ? MedicalHistoryCard(
                  summary: s,
                  caseSheet: caseSheet,
                  allergies: allergies,
                  onEdit: edit,
                  dental: isDentist
                      ? (
                          line: omCardLine(omHistory),
                          onOpen: () => showOmHistoryDialog(
                            context,
                            p,
                            existing: omHistory,
                          ),
                        )
                      : null,
                )
              : null;
          final overview = DetailsColumns(
            wide: wide,
            left: [history, card(_Sub.files)],
            right: [assignedDoctors, card(_Sub.visits), card(_Sub.payments)],
            narrow: [
              history,
              card(_Sub.visits),
              card(_Sub.payments),
              card(_Sub.files),
              assignedDoctors,
            ],
          );

          Widget clinicalScreen() {
            if (isDentist) {
              final plan = items.isEmpty
                  ? NoPlanCard(patient: p, onCreatePlan: editPlan)
                  : TreatmentPlanCard(
                      summary: s,
                      items: items,
                      onEditPlan: editPlan,
                      onBook: newVisit,
                    );
              final records = DentalRecordsCard(patient: p);
              final procedures = DentalProceduresCard(patient: p);
              return DetailsStack([
                ToothChartPreviewCard(patient: p),
                DetailsColumns(
                  wide: wide,
                  left: [plan, procedures],
                  right: [records],
                  narrow: [plan, records, procedures],
                ),
              ]);
            }
            if (isPhysio) {
              return DetailsColumns(
                wide: wide,
                left: [MuscleChartCard(patient: p)],
                right: [PhysioPhotosCard(patient: p)],
              );
            }
            return _CaseSheetCard(
              onOpen: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => HomeopathyPatientDetailsScreen(patient: p),
                ),
              ),
            );
          }

          Widget screen(_Sub sub) => SingleChildScrollView(
            key: PageStorageKey<String>('patient-${s.id}-${sub.name}'),
            padding: padding.copyWith(top: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: CruSpace.s16),
                  child: Semantics(
                    header: true,
                    child: MorphTag.text(
                      id: 'title',
                      text: sub.label,
                      style: CruType.title2.tint(c.label),
                    ),
                  ),
                ),
                switch (sub) {
                  _Sub.visits => DetailsStack([
                    VisitsList(
                      summary: s,
                      now: now,
                      showClinical: clinical,
                      onOpen: openVisit,
                    ),
                    if (orphanSessions.isNotEmpty)
                      SessionHistoryCard(patient: p, sessions: orphanSessions),
                  ]),
                  _Sub.files => PatientFilesCard(
                    patient: p,
                    showImaging: showImaging,
                    full: true,
                    visits: s.visits,
                  ),
                  _Sub.payments => PaymentsTab(
                    summary: s,
                    wide: wide,
                    onRecordPayment: recordPayment,
                    onNewBill: canBill ? newBill : null,
                    showRecords: canBill,
                  ),
                },
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: padding.copyWith(
                  bottom: phone ? CruSpace.s12 : CruSpace.s16,
                ),
                child: PatientDetailsHeader(
                  summary: s,
                  allergies: allergies,
                  onBack: open == null ? widget.onBack : _close,
                  backLabel: open == null ? null : 'Overview',
                  onCall: () => PatientActions.call(context, p),
                  onWhatsApp: () => PatientActions.whatsApp(context, p),
                  menu: menu,
                  onNewVisit: canBook ? newVisit : null,
                  actions: [if (isDentist) _RecallButton(patient: p)],
                  tabs: tabs.length < 2
                      ? null
                      : CruSegmentedControl<_Tab>(
                          semanticLabel: 'Patient details',
                          segments: [
                            for (final t in tabs) CruSegment(t, t.label),
                          ],
                          selected: tab,
                          onChanged: _go,
                        ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final area = Offset.zero & box.biggest;
                    final flying = {for (final f in _flights) f.id};
                    return Stack(
                      key: _area,
                      children: [
                        // The pages stay laid out under a sub-screen, so
                        // Overview keeps its scroll; they fade away as the
                        // box grows.
                        AnimatedBuilder(
                          animation: _t,
                          builder: (context, child) => IgnorePointer(
                            ignoring: open != null,
                            child: Opacity(
                              opacity: open == null
                                  ? 1
                                  : 1 -
                                        const Interval(
                                          0,
                                          0.5,
                                        ).transform(_t.value),
                              child: child,
                            ),
                          ),
                          child: SwipePages<_Tab>(
                            values: tabs,
                            value: tab,
                            onChanged: _go,
                            builder: (context, t) => SingleChildScrollView(
                              key: PageStorageKey<String>(
                                'patient-${s.id}-${t.name}',
                              ),
                              padding: padding.copyWith(top: 0),
                              child: t == _Tab.overview
                                  ? overview
                                  : clinicalScreen(),
                            ),
                          ),
                        ),
                        if (open != null)
                          AnimatedBuilder(
                            animation: _t,
                            builder: (context, child) => MorphBox(
                              t: _t.value,
                              from: _from,
                              area: area,
                              settled: _morph.isCompleted,
                              // The card's copy in the box, without what
                              // flies.
                              source: MorphScope(
                                side: MorphSide.source,
                                group: 'copy',
                                registry: null,
                                hidden: flying,
                                child: sources[open]!,
                              ),
                              child: child!,
                            ),
                            child: MorphScope(
                              side: MorphSide.destination,
                              group: open.name,
                              registry: _registry,
                              hidden: _morph.isCompleted ? const {} : flying,
                              child: KeyedSubtree(
                                key: ValueKey(open),
                                child: RepaintBoundary(
                                  key: _page,
                                  child: screen(open),
                                ),
                              ),
                            ),
                          ),
                        // Shared elements on their way between the card
                        // and the sub-screen.
                        if (open != null && _flights.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ClipRect(
                                child: Offstage(
                                  offstage: _morph.isCompleted,
                                  child: AnimatedBuilder(
                                    animation: _t,
                                    builder: (context, _) => MorphFlights(
                                      t: _t.value,
                                      flights: _flights,
                                    ),
                                  ),
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
        },
      ),
    );
  }
}

/// Dentists: the patient's next recall, set or changed from the header.
/// "Recall · 12 Apr" ("Recall overdue · 12 Apr" once past); an icon
/// button on phones.
class _RecallButton extends ConsumerWidget {
  const _RecallButton({required this.patient});

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
    final overdue = due != null && due.isBefore(DateTime.now());
    final label = due == null
        ? 'Recall'
        : '${overdue ? 'Recall overdue' : 'Recall'} · '
              '${DentalFormat.shortDate(due)}';
    void edit() =>
        showSetRecallDialog(context, patient: patient, existing: next);
    if (MediaQuery.sizeOf(context).width < PatientDetailsHeader.phoneBelow) {
      return CruSquareButton(
        icon: RecIcons.recall,
        secondary: true,
        semanticLabel: due == null ? 'Set a recall' : '$label, change it',
        tooltip: label,
        onPressed: edit,
      );
    }
    return CruCapsuleButton(
      label: label,
      icon: RecIcons.recall,
      height: CruSize.control,
      semanticLabel: due == null ? 'Set a recall' : '$label, change it',
      onPressed: edit,
    );
  }
}

/// Homeopaths: the case sheet, which opens full screen.
class _CaseSheetCard extends StatelessWidget {
  const _CaseSheetCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      semanticLabel: 'Case sheet',
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text('Case sheet', style: CruType.headline.tint(c.label)),
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          CruCapsuleButton(label: 'Open case sheet', onPressed: onOpen),
        ],
      ),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: _padding,
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [DetailsBackLink(onBack: onBack)]),
          const SizedBox(height: CruSpace.s12),
          const Row(
            children: [
              SkeletonBox(
                width: CruSize.monogramPreview,
                height: CruSize.monogramPreview,
                circle: true,
              ),
              SizedBox(width: CruSpace.s16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 220, height: 24),
                  SizedBox(height: CruSpace.s8),
                  SkeletonBox(width: 280, height: 14),
                ],
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 380, height: CruSize.segmentHeight),
          ),
          const SizedBox(height: CruSpace.s16),
          const SkeletonCard(rows: 3),
          const SizedBox(height: CruSpace.cardGap),
          const SkeletonCard(rows: 2),
        ],
      ),
    );
  }
}

/// Not found / couldn't load: a calm line and the way back.
class _Missing extends StatelessWidget {
  const _Missing({required this.onBack, required this.message});
  final VoidCallback onBack;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: _padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailsBackLink(onBack: onBack),
          const SizedBox(height: CruSpace.s32),
          Text(message, style: CruType.body.tint(c.label2)),
          const SizedBox(height: CruSpace.s12),
          CruLink(label: 'Back to patients', onPressed: onBack),
        ],
      ),
    );
  }
}
