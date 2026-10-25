import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:doctor_management_app/core/services/access_audit_service.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/appointments/presentation/schedule_visit_sheet.dart';
import 'package:doctor_management_app/features/appointments/presentation/session_details_sheet.dart';
import 'package:doctor_management_app/features/patients/presentation/add_patient.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/homeopathy_case_taking_sheet.dart';
import 'package:doctor_management_app/features/files/presentation/patient_files_card.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/session_history_card.dart';
import 'package:doctor_management_app/features/scribe/data/providers/scribe_providers.dart';

/// Widest the page grows on desktop; it reads as a column, not a sheet.
const double _maxWidth = 760;

class HomeopathyPatientDetailsScreen extends ConsumerStatefulWidget {
  final Patient patient;

  const HomeopathyPatientDetailsScreen({super.key, required this.patient});

  @override
  ConsumerState<HomeopathyPatientDetailsScreen> createState() =>
      _HomeopathyPatientDetailsScreenState();
}

class _HomeopathyPatientDetailsScreenState
    extends ConsumerState<HomeopathyPatientDetailsScreen> {
  late String _note = widget.patient.notes;

  @override
  void initState() {
    super.initState();
    AccessAuditService.instance.patientViewed(widget.patient.id);
  }

  Future<void> _openNoteEditor() async {
    final controller = TextEditingController(text: _note);
    final c = context.cru;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: CruSpace.s20,
          right: CruSpace.s20,
          top: CruSpace.s14,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + CruSpace.s20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: CruSpace.s32 + CruSpace.s12,
                height: CruSpace.s4,
                margin: const EdgeInsets.only(bottom: CruSpace.s16),
                decoration: ShapeDecoration(
                  color: c.track,
                  shape: cruShape(CruRadius.full),
                ),
              ),
            ),
            Text("Doctor's note", style: CruType.title2.tint(c.label)),
            const SizedBox(height: CruSpace.s12),
            TextField(
              controller: controller,
              maxLines: 5,
              autofocus: true,
              style: CruType.input.tint(c.label),
              decoration: const InputDecoration(
                hintText: 'General clinical observations',
              ),
            ),
            const SizedBox(height: CruSpace.s16),
            CruButton(
              label: 'Save note',
              expand: true,
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            ),
          ],
        ),
      ),
    );

    if (result != null && result != _note) {
      setState(() => _note = result);
      await ref
          .read(patientRepositoryProvider)
          .updateDoctorsNote(widget.patient.id, result);
    }
  }

  Future<void> _scheduleSession() async {
    final scheduled = await showScheduleVisitSheet(
      context,
      patient: widget.patient,
      visitRepository: ref.read(visitRepositoryProvider),
    );

    if (!scheduled || !mounted) return;
    ref.invalidate(visitsForPatientProvider(widget.patient.id));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Consultation scheduled for ${widget.patient.fullName}'),
      ),
    );
  }

  Future<void> _editPatient(Patient currentPatient) async {
    final updated = await showEditPatientSheet(
      context,
      patient: currentPatient,
      repository: ref.read(patientRepositoryProvider),
    );
    if (updated == true && mounted) {
      ref.invalidate(patientsStreamProvider);
    }
  }

  Future<void> _deletePatient(Patient currentPatient) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Delete ${currentPatient.fullName}?',
        leading: const CruIconTile(
          icon: CruIcons.warning,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Delete',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Text(
            'Their record, case sheet and visit history are removed from '
            'this clinic.',
            style: CruType.text.tint(ctx.cru.label2),
          ),
        ),
      ),
    );

    if (confirm == true && mounted) {
      await ref
          .read(patientRepositoryProvider)
          .deletePatient(currentPatient.id);
      if (!mounted) return;
      ref.invalidate(patientsStreamProvider);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patientsAsync = ref.watch(patientsStreamProvider);
    final patient = patientsAsync.maybeWhen(
      data: (list) {
        for (final p in list) {
          if (p.id == widget.patient.id) return p;
        }
        return widget.patient;
      },
      orElse: () => widget.patient,
    );

    final visitsAsync = ref.watch(visitsForPatientProvider(patient.id));
    final caseSheetAsync = ref.watch(homeopathyCaseSheetProvider(patient.id));
    final sessions =
        ref.watch(sessionHistoryProvider(patient.id)).value ?? const [];

    Widget centred(Widget child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: child,
      ),
    );

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            centred(
              _HomeopathyTopBar(
                onEdit: () => _editPatient(patient),
                onDelete: () => _deletePatient(patient),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s20,
                  CruSpace.s8,
                  CruSpace.s20,
                  108,
                ),
                physics: const ClampingScrollPhysics(),
                children: [
                  centred(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PatientHeaderCard(patient: patient),
                        const SizedBox(height: CruSpace.cardGap),
                        caseSheetAsync.when(
                          loading: () => const CruCard(
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (err, _) => CruCard(
                            child: Text(
                              "Couldn't load the case sheet.",
                              style: CruType.text.tint(c.label2),
                            ),
                          ),
                          data: (caseSheet) => _HomeopathyCaseSheetCard(
                            patient: patient,
                            caseSheet: caseSheet,
                            onOpenCaseTaking: () async {
                              final updated =
                                  await HomeopathyCaseTakingSheet.show(
                                    context,
                                    patient: patient,
                                    initialCaseSheet: caseSheet,
                                  );
                              if (updated == true && mounted) {
                                ref.invalidate(
                                  homeopathyCaseSheetProvider(patient.id),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: CruSpace.cardGap),
                        // Consultations recorded with the AI scribe.
                        if (sessions.isNotEmpty) ...[
                          SessionHistoryCard(
                            patient: patient,
                            sessions: sessions,
                          ),
                          const SizedBox(height: CruSpace.cardGap),
                        ],
                        _HomeoDoctorsNoteCard(
                          note: _note,
                          onTap: _openNoteEditor,
                        ),
                        const SizedBox(height: CruSpace.cardGap),
                        // Every file and report added for this patient.
                        PatientFilesCard(patient: patient),
                        const SizedBox(height: CruSpace.s20),
                        const _SectionHeading(title: 'Contact'),
                        const SizedBox(height: CruSpace.s10),
                        _ContactCard(
                          phone: patient.phone,
                          email: patient.email,
                        ),
                        const SizedBox(height: CruSpace.s20),
                        const _SectionHeading(title: 'Consultations'),
                        const SizedBox(height: CruSpace.s10),
                        visitsAsync.when(
                          loading: () => const CruCard(
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (e, st) => CruCard(
                            child: Text(
                              "Couldn't load consultations.",
                              style: CruType.text.tint(c.label2),
                            ),
                          ),
                          data: (visits) {
                            if (visits.isEmpty) {
                              return CruCard(
                                child: Column(
                                  children: [
                                    CruIcon(
                                      CruIcons.calendar,
                                      size: CruSpace.s32,
                                      color: c.label3,
                                    ),
                                    const SizedBox(height: CruSpace.s8),
                                    Text(
                                      'No consultations yet',
                                      style: CruType.callout.w600.tint(c.label),
                                    ),
                                    const SizedBox(height: CruSpace.s4),
                                    Text(
                                      'Book the first one below.',
                                      style: CruType.caption.tint(c.label2),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Column(
                              children: [
                                for (final v in visits)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: CruSpace.s8,
                                    ),
                                    child: _VisitItemCard(
                                      visit: v,
                                      onTap: () => showSessionDetailsSheet(
                                        context,
                                        VisitWithPatient(
                                          visit: v,
                                          patient: patient,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          CruSpace.s12,
          CruSpace.s16,
          CruSpace.s16,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: SafeArea(
          child: centred(
            Row(
              children: [
                Expanded(
                  child: CruButton(
                    label: 'Add note',
                    kind: CruButtonKind.secondary,
                    expand: true,
                    onPressed: _openNoteEditor,
                  ),
                ),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: CruButton(
                    label: 'Book consultation',
                    icon: CruIcons.calendar,
                    expand: true,
                    onPressed: _scheduleSession,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeopathyTopBar extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HomeopathyTopBar({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s12,
        vertical: CruSpace.s8,
      ),
      child: Row(
        children: [
          CruIconButton(
            icon: CruIcons.chevronLeft,
            onPressed: () => Navigator.pop(context),
            semanticLabel: 'Back',
          ),
          const SizedBox(width: CruSpace.s4),
          Expanded(
            child: Text('Case sheet', style: CruType.title2.tint(c.label)),
          ),
          CruPill(
            text: 'Homeopathy',
            background: c.inset,
            foreground: c.label2,
          ),
          const SizedBox(width: CruSpace.s6),
          CruIconButton(
            icon: CruIcons.pen,
            onPressed: onEdit,
            semanticLabel: 'Edit patient',
          ),
          CruIconButton(
            icon: FileIcons.trash,
            onPressed: onDelete,
            semanticLabel: 'Delete patient',
          ),
        ],
      ),
    );
  }
}

class _PatientHeaderCard extends StatelessWidget {
  final Patient patient;

  const _PatientHeaderCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Row(
        children: [
          CruMonogram(
            name: patient.fullName,
            size: CruSize.monogramUpNext,
            background: c.track,
            foreground: c.label2,
          ),
          const SizedBox(width: CruSpace.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.fullName, style: CruType.headline.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(
                  '${patient.age} years · ${patient.gender}',
                  style: CruType.caption.tabular.tint(c.label2),
                ),
                if (patient.diagnosis.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s6),
                  Wrap(
                    spacing: CruSpace.s4,
                    runSpacing: CruSpace.s4,
                    children: [
                      for (final d in patient.diagnosis)
                        CruPill(
                          text: d,
                          background: c.inset,
                          foreground: c.label2,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeopathyCaseSheetCard extends StatelessWidget {
  final Patient patient;
  final HomeopathyCaseSheet? caseSheet;
  final VoidCallback onOpenCaseTaking;

  const _HomeopathyCaseSheetCard({
    required this.patient,
    required this.caseSheet,
    required this.onOpenCaseTaking,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final isFemale = patient.gender.toLowerCase().trim() == 'female';
    final sheet = caseSheet;
    final completedSections =
        sheet?.completedSectionsCount(isFemale: isFemale) ?? 0;
    final totalSections =
        sheet?.totalSectionsCount(isFemale: isFemale) ?? (isFemale ? 15 : 14);
    final remedy = sheet?.prescriptionNotes.prescribedRemedy.trim() ?? '';
    final thermal =
        sheet?.generalSymptoms.thermalState ??
        HomeopathyThermalState.unspecified;
    final done = sheet?.isCompleted ?? false;

    Widget tag(String text) =>
        CruPill(text: text, background: c.inset, foreground: c.label2);

    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CruIconTile(icon: CruIcons.fileText, tone: CruTileTone.neutral),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Text(
                  'Clinical case sheet',
                  style: CruType.headline.tint(c.label),
                ),
              ),
              CruPill(
                text: sheet == null
                    ? 'Not started'
                    : done
                    ? 'Complete'
                    : '$completedSections of $totalSections sections',
                // Green means done; anything short of that stays neutral.
                background: done ? c.greenTint : c.inset,
                foreground: done ? c.greenText : c.label2,
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          if (sheet != null && sheet.overview.chiefProblem.isNotEmpty) ...[
            Text(
              'Chief complaint: ${sheet.overview.chiefProblem}',
              style: CruType.callout.w600.tint(c.label),
            ),
            const SizedBox(height: CruSpace.s6),
          ],
          Wrap(
            spacing: CruSpace.s6,
            runSpacing: CruSpace.s4,
            children: [
              if (sheet != null) tag(sheet.overview.caseType.label),
              if (thermal != HomeopathyThermalState.unspecified)
                tag(thermal.label),
              if (remedy.isNotEmpty) tag('Rx: $remedy'),
              if (sheet != null && sheet.followUp.responseRating.isNotEmpty)
                tag(sheet.followUp.responseRating),
              if (sheet != null &&
                  sheet.followUp.nextPrescriptionPlan.isNotEmpty)
                tag(sheet.followUp.nextPrescriptionPlan),
              if (sheet != null &&
                  sheet.prescriptionNotes.totalityOfSymptoms.isNotEmpty)
                tag('Totality written'),
            ],
          ),
          const SizedBox(height: CruSpace.s14),
          CruButton(
            label: sheet != null ? 'Review case sheet' : 'Start case taking',
            icon: sheet != null ? CruIcons.pen : CruIcons.plus,
            expand: true,
            onPressed: onOpenCaseTaking,
          ),
        ],
      ),
    );
  }
}

class _HomeoDoctorsNoteCard extends StatelessWidget {
  final String note;
  final VoidCallback onTap;

  const _HomeoDoctorsNoteCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final hasNote = note.trim().isNotEmpty;

    return CruPressable(
      onTap: onTap,
      builder: (context, hovered) => CruCard(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "DOCTOR'S NOTE",
                    style: CruType.groupLabel.tint(c.label3),
                  ),
                ),
                CruIcon(
                  hasNote ? CruIcons.pen : CruIcons.plus,
                  size: CruSpace.s16,
                  color: c.label2,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s8),
            Text(
              hasNote ? note : 'Tap to add notes or general observations.',
              style: CruType.text.tint(hasNote ? c.label : c.label3),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final String phone;
  final String email;

  const _ContactCard({required this.phone, required this.email});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruCard(
      padding: const EdgeInsets.all(CruSpace.s16),
      child: Column(
        children: [
          Row(
            children: [
              CruIcon(CruIcons.phone, size: CruSpace.s18, color: c.label3),
              const SizedBox(width: CruSpace.s10),
              Text(
                phone.isNotEmpty ? phone : 'No phone number',
                style: CruType.text.tabular.tint(c.label),
              ),
            ],
          ),
          if (email.isNotEmpty) ...[
            Divider(height: CruSpace.s20, color: c.separator),
            Row(
              children: [
                Icon(Icons.email_outlined, size: CruSpace.s18, color: c.label3),
                const SizedBox(width: CruSpace.s10),
                Text(email, style: CruType.text.tint(c.label)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VisitItemCard extends StatelessWidget {
  final Visit visit;
  final VoidCallback onTap;

  const _VisitItemCard({required this.visit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final when = DateFormat(
      'EEE, d MMM yyyy · h:mm a',
    ).format(visit.scheduledStart);
    final type = visit.treatmentType?.trim() ?? '';

    return CruPressable(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s14,
          vertical: CruSpace.s12,
        ),
        decoration: BoxDecoration(
          color: hovered ? c.hoverFill : c.surface,
          borderRadius: BorderRadius.circular(CruRadius.control),
          border: Border.all(color: c.cardBorder),
        ),
        child: Row(
          children: [
            CruIconTile(icon: CruIcons.calendar, tone: CruTileTone.neutral),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.isNotEmpty ? type : 'Consultation',
                    style: CruType.callout.w600.tint(c.label),
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Text(when, style: CruType.caption.tabular.tint(c.label2)),
                ],
              ),
            ),
            CruIcon(CruIcons.chevronRight, size: CruSpace.s18, color: c.label3),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;

  const _SectionHeading({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: CruType.groupLabel.tint(context.cru.label3),
    );
  }
}
