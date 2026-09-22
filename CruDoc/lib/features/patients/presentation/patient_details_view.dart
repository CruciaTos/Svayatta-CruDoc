import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/glance_card.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/skeleton.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/dental_patient_details_screen.dart';
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
import 'package:doctor_management_app/features/patients/presentation/widgets/details/medical_history_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/payments_block.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/treatment_plan_card.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/visits_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Main-area padding for Patient details (the dashboard's, 24 on top).
final EdgeInsets _padding = CruSpace.mainPadding.copyWith(top: CruSpace.s24);

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

/// Patient details as a pushed route (Day theme, canvas background).
class PatientDetailsScreen extends StatelessWidget {
  const PatientDetailsScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CruTheme.day(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.cru.canvas,
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
    final isDentist = specialty == DoctorSpecialtyType.dentist;
    final isHomeopath = specialty == DoctorSpecialtyType.homeopathy;

    // Dental plan (dentists only). Declined items are dropped.
    final plan = isDentist ? ref.watch(patientTreatmentPlanProvider(s.id)) : null;
    final planValue = plan?.value;
    final planLoading = plan != null && planValue == null && !plan.hasError;
    final items = planValue == null
        ? const <TreatmentPlanLineItemModel>[]
        : DentalPlan.active(planValue);

    // Homeopathy case sheet (homeopaths only): allergies and history.
    final caseSheet =
        isHomeopath ? ref.watch(homeopathyCaseSheetProvider(s.id)).value : null;
    final allergies = KnownAllergies.parse(caseSheet?.medicalHistory.allergies);

    Future<void> push(Widget screen) async {
      await Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
      if (isDentist && context.mounted) {
        ref.invalidate(patientTreatmentPlanProvider(s.id));
      }
    }

    void newVisit() => PatientActions.newVisit(context, ref, p);
    void edit() => PatientActions.edit(context, ref, p);
    void recordPayment() => PatientActions.recordPayment(context, ref, s);

    final Widget planOrPayments = planLoading
        ? const SkeletonCard(rows: 3)
        : items.isNotEmpty
            ? TreatmentPlanCard(
                summary: s,
                items: items,
                onEditPlan: () => push(DentalPatientDetailsScreen(patient: p)),
                onBook: newVisit,
                onRecordPayment: recordPayment,
              )
            : PaymentsCard(summary: s, onRecordPayment: recordPayment);
    final notes = ClinicalNotesCard(summary: s, now: now);
    final visits = VisitsCard(
      summary: s,
      now: now,
      onUpdate: (v) => PatientActions.updateVisit(context, v, p),
    );
    final history = MedicalHistoryCard(
      summary: s,
      caseSheet: caseSheet,
      onEdit: edit,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth - _padding.horizontal >=
            CruBreakpoint.detailsTwoColumn;
        return SingleChildScrollView(
          padding: _padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailsTopBar(
                patientName: p.fullName,
                onBack: onBack,
                onEdit: edit,
                onNewVisit: newVisit,
                onDentalChart: isDentist
                    ? () => push(DentalPatientDetailsScreen(patient: p))
                    : null,
                onCaseSheet: isHomeopath
                    ? () => push(HomeopathyPatientDetailsScreen(patient: p))
                    : null,
                onDelete: () async {
                  final deleted = await PatientActions.delete(context, ref, p);
                  if (deleted) onBack();
                },
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
                    Expanded(child: _Stack([planOrPayments, notes])),
                    const SizedBox(width: CruSpace.cardGap),
                    SizedBox(
                      width: CruSize.rightColumn,
                      child: _Stack([visits, history]),
                    ),
                  ],
                )
              else
                _Stack([planOrPayments, visits, notes, history]),
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
