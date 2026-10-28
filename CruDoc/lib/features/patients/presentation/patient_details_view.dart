import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/services/access_audit_service.dart';
import 'package:doctor_management_app/features/dental/specialties/oralmed/oralmed_history.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/tooth_chart_card.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_card.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/homeopathy_patient_details_screen.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_actions.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/clinical_notes_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_top_bar.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/facts_strip.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/identity_header.dart';
import 'package:doctor_management_app/features/settings/data/appearance_provider.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/medical_history_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/payments_block.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/session_history_card.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/treatment_plan_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visits_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/assigned_doctors_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/physio_photos_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/muscle_chart_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
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
const double _phoneWidth = 600;

/// Patient details content (no Scaffold): top bar, identity header,
/// facts strip, then the cards in two columns when there is room.
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

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({required this.summary, required this.onBack});

  final PatientSummary summary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final p = s.patient;
    final now = ref.watch(dashboardNowProvider);
    final specialty = ref.watch(activeDoctorSpecialtyProvider).value?.type;
    final isDentist = ref.watch(isDentistProvider);
    // Clinical parts are for people whose role includes clinical records.
    final clinical = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalView),
    );
    final canEdit = ref.watch(clinicCanProvider(ClinicPermission.patientsEdit));
    final canBook = ref.watch(clinicCanProvider(ClinicPermission.schedule));
    final canClinicalEdit = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalEdit),
    );
    final canBill = ref.watch(clinicCanProvider(ClinicPermission.billing));
    final isPhysio = clinical && ref.watch(isPhysiotherapyProvider);
    final isHomeopath = clinical && specialty == DoctorSpecialtyType.homeopathy;
    // Scans and reports for dentists with radiology enabled.
    // Who treats this patient. Hides itself unless the clinic scopes its
    // doctors to the patients they treat.
    // Left out of the layout otherwise, so its empty slot leaves no gap.
    final assignedDoctors =
        ref.watch(clinicAccessProvider).value?.clinicalAccessScope == 'assigned'
        ? AssignedDoctorsCard(
            patientId: s.id,
            assignedDoctorUids: p.assignedDoctorUids,
          )
        : null;
    // Imaging studies show inside the Files card: one card for everything
    // filed to the patient.
    final showImaging = ref.watch(hasDentalRadiologyProvider);

    // Dental plan (dentists only). Declined items are dropped.
    final plan = isDentist
        ? ref.watch(patientTreatmentPlanProvider(s.id))
        : null;
    final planValue = plan?.value;
    final planLoading = plan != null && planValue == null && !plan.hasError;
    final items = planValue == null
        ? const <TreatmentPlanLineItemModel>[]
        : DentalPlan.active(planValue);

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

    Future<void> push(Widget screen) async {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => screen));
      if (isDentist && context.mounted) {
        ref.invalidate(patientTreatmentPlanProvider(s.id));
      }
    }

    void newVisit() => PatientActions.newVisit(context, ref, p);
    void edit() => PatientActions.edit(context, ref, p);
    void recordPayment() => PatientActions.recordPayment(context, ref, s);

    // The treatment plan opens from its Clinical records tile.
    final Widget planOrPayments = PaymentsCard(
      summary: s,
      onRecordPayment: recordPayment,
    );
    final notes = clinical ? ClinicalNotesCard(summary: s, now: now) : null;
    // Dentists: the tooth chart, their procedures, and a way into a plan.
    final chart = isDentist ? ToothChartCard(patient: p) : null;
    final records = isDentist ? DentalRecordsCard(patient: p) : null;
    final physioPhotos = isPhysio ? PhysioPhotosCard(patient: p) : null;
    // X-rays, photos and reports from the Files screen.
    final files = clinical || showImaging
        ? PatientFilesCard(patient: p, showImaging: showImaging)
        : null;
    final muscleChart = isPhysio ? MuscleChartCard(patient: p) : null;
    // Consultations recorded with the AI scribe; hidden until there is one.
    final sessions = clinical
        ? ref.watch(sessionHistoryProvider(s.id)).value
        : null;
    final sessionHistory = sessions == null || sessions.isEmpty
        ? null
        : SessionHistoryCard(patient: p, sessions: sessions);
    final visits = VisitsCard(
      summary: s,
      now: now,
      onUpdate: (v) => PatientActions.updateVisit(context, v, p),
    );
    final history = clinical
        ? MedicalHistoryCard(summary: s, caseSheet: caseSheet, onEdit: edit)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < _phoneWidth
            ? _phonePadding
            : _padding;
        final wide =
            constraints.maxWidth - padding.horizontal >=
            CruBreakpoint.detailsTwoColumn;
        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailsTopBar(
                patientName: p.fullName,
                onBack: onBack,
                onEdit: canEdit ? edit : null,
                onNewVisit: canBook ? newVisit : null,
                onNewBill: canBill
                    ? () => showDesktopCreateInvoiceDialog(
                        context,
                        initialPatient: p,
                      )
                    : null,
                onPrescription: canClinicalEdit
                    ? () {
                        final profile = ref.read(doctorProfileProvider).value;
                        final user = FirebaseAuth.instance.currentUser;
                        final cfg = DoctorLetterheadConfig.fromProfileData(
                          profile,
                          user,
                        );
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => PrescriptionGenerationSheet(
                            letterheadConfig: cfg,
                            initialPatient: p,
                          ),
                        );
                      }
                    : null,
                onReport: canClinicalEdit
                    ? () {
                        final profile = ref.read(doctorProfileProvider).value;
                        final user = FirebaseAuth.instance.currentUser;
                        final cfg = DoctorLetterheadConfig.fromProfileData(
                          profile,
                          user,
                        );
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => MedicalReportGenerationSheet(
                            letterheadConfig: cfg,
                            initialPatient: p,
                          ),
                        );
                      }
                    : null,
                // Dentists: the procedure log opens from the top bar.
                onProcedures: isDentist
                    ? () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          insetPadding: const EdgeInsets.all(CruSpace.s24),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: SingleChildScrollView(
                              child: DentalProceduresCard(patient: p),
                            ),
                          ),
                        ),
                      )
                    : null,
                onCertificate: canClinicalEdit
                    ? () => showCertificateDialog(context, patient: p)
                    : null,
                // Dentists have the tooth chart on the page itself.
                onDentalChart: null,
                onCaseSheet: isHomeopath
                    ? () => push(HomeopathyPatientDetailsScreen(patient: p))
                    : null,
                onDelete: canEdit
                    ? () async {
                        final deleted = await PatientActions.delete(
                          context,
                          ref,
                          p,
                        );
                        if (deleted) onBack();
                      }
                    : null,
              ),
              const SizedBox(height: CruSpace.stackGap),
              IdentityHeader(
                summary: s,
                allergies: allergies,
                onCall: () => PatientActions.call(context, p),
                onWhatsApp: () => PatientActions.whatsApp(context, p),
              ),
              const SizedBox(height: CruSpace.stackGap),
              PatientFactsStrip(
                summary: s,
                now: now,
                plan: DentalPlan.progress(items),
                planLoading: planLoading,
              ),
              const SizedBox(height: CruSpace.stackGap),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Stack([
                        ?chart,
                        ?sessionHistory,
                        ?muscleChart,
                        planOrPayments,
                        ?notes,
                      ]),
                    ),
                    const SizedBox(width: CruSpace.cardGap),
                    SizedBox(
                      width: CruSize.rightColumn,
                      child: _Stack([
                        ?records,
                        ?assignedDoctors,
                        visits,
                        ?files,
                        ?physioPhotos,
                        ?history,
                      ]),
                    ),
                  ],
                )
              else
                _Stack([
                  ?assignedDoctors,
                  ?chart,
                  ?records,
                  ?sessionHistory,
                  ?muscleChart,
                  planOrPayments,
                  visits,
                  ?files,
                  ?physioPhotos,
                  ?notes,
                  ?history,
                ]),
            ],
          ),
        );
      },
    );
  }
}

/// Cards stacked with the card gap.
class _Stack extends StatelessWidget {
  const _Stack(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: CruSpace.cardGap),
        children[i],
      ],
    ],
  );
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
          const SizedBox(height: CruSpace.stackGap),
          const Row(
            children: [
              SkeletonBox(
                width: CruSize.monogramProfile,
                height: CruSize.monogramProfile,
                circle: true,
              ),
              SizedBox(width: CruSpace.s20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 240, height: 28),
                  SizedBox(height: CruSpace.s10),
                  SkeletonBox(width: 280, height: 14),
                  SizedBox(height: CruSpace.s12),
                  SkeletonBox(width: 200, height: CruSize.chip),
                ],
              ),
            ],
          ),
          const SizedBox(height: CruSpace.stackGap),
          const GlanceStrip(
            semanticLabel: 'Loading key facts',
            cells: [
              GlanceCellSkeleton(ring: true),
              GlanceCellSkeleton(),
              GlanceCellSkeleton(),
              GlanceCellSkeleton(),
            ],
          ),
          const SizedBox(height: CruSpace.stackGap),
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
