import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_dialog.dart';
import 'package:doctor_management_app/features/dental/specialties/prostho/lab_case_models.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/mobile/tasks/tasks_logic.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/pacs_connection.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/pacs_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/rad_import_flow.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/phrase_library.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/template_manager.dart';
import 'package:doctor_management_app/features/radiology/presentation/rvg_capture_dialog.dart';
import 'package:doctor_management_app/features/radiology/viewer/thumbnail_strip.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';

/// Rebuilt Tasks tab for the mobile shell: one unified to-do list with
/// source pill filter, a recently-done strip, search with filter icon, and flat list.
class MobileTasksScreen extends ConsumerStatefulWidget {
  const MobileTasksScreen({super.key, required this.enabledModules});

  final List<String> enabledModules;

  @override
  ConsumerState<MobileTasksScreen> createState() => _MobileTasksScreenState();
}

/// Size of a scan's pictures on this device; null when none are here yet
/// (the row then shows no size).
final _studyBytesProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  studyId,
) async {
  final s = await ref.watch(radStudyProvider(studyId).future);
  if (s == null || s.images.isEmpty) return null;
  final repo = ref.watch(radiologyRepositoryProvider);
  final doctorId = ref.watch(radDoctorIdProvider);
  var total = 0;
  try {
    for (final i in s.images) {
      final f = await repo.fileOf(doctorId, s.id, i.path);
      if (await f.exists()) total += await f.length();
    }
  } catch (_) {
    return null;
  }
  return total > 0 ? total : null;
});

/// "840 KB", "12.4 MB".
String _fileSize(int bytes) {
  const kb = 1024;
  const mb = 1024 * kb;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / kb).ceil()} KB';
}

class _MobileTasksScreenState extends ConsumerState<MobileTasksScreen> {
  TaskSourceFilter _sourceFilter = TaskSourceFilter.all;
  TaskStatusFilter _statusFilter = TaskStatusFilter.any;
  TaskTimeFilter _timeFilter = TaskTimeFilter.any;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Scan pictures for the Recent activity cards.
  late final RadThumbCache _thumbs = RadThumbCache(
    ref.read(radiologyProvider).thumbSourceOf,
  );

  @override
  void dispose() {
    _search.dispose();
    _thumbs.dispose();
    super.dispose();
  }

  void _openAddSheet(
    BuildContext context, {
    required bool radiology,
    required bool dental,
  }) {
    final actions = <MobileSheetAction>[
      if (radiology) ...[
        MobileSheetAction(
          label: 'Import scans',
          icon: RadIcons.worklist,
          tone: MobileTone.indigo,
          onTap: () => runRadImport(context, ref),
        ),
        MobileSheetAction(
          label: 'Capture RVG',
          icon: CruIcons.plus,
          tone: MobileTone.teal,
          onTap: () => showRvgCaptureDialog(mobileRoot(context)),
        ),
        MobileSheetAction(
          label: 'New template',
          icon: RadIcons.template,
          tone: MobileTone.sky,
          onTap: () => showRadTemplateManager(mobileRoot(context)),
        ),
        MobileSheetAction(
          label: 'New phrase',
          icon: RadIcons.phrase,
          tone: MobileTone.slate,
          onTap: () => showRadPhraseLibrary(mobileRoot(context)),
        ),
      ],
      if (dental)
        MobileSheetAction(
          label: 'New treatment plan',
          icon: DentalIcons.plan,
          tone: MobileTone.blue,
          onTap: () async {
            final patient = await showPatientPickerDialog(
              mobileRoot(context),
              title: 'Plan treatment for',
            );
            if (patient == null || !context.mounted) return;
            await showTreatmentPlanDialog(
              mobileRoot(context),
              patient: patient,
            );
            ref.invalidate(clinicTreatmentPlansProvider);
          },
        ),
    ];

    if (actions.isEmpty) return;
    showMobileActionSheet(context, title: 'New task', actions: actions);
  }

  void _openFilterModal(BuildContext context, TaskSourceFilter source) {
    final statusOptions = statusFiltersFor(source);
    final root = mobileRoot(context);

    showModalBottomSheet<void>(
      context: root,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (sheetContext) {
        final c = sheetContext.cru;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              CruSpace.s8,
              0,
              CruSpace.s8,
              CruSpace.s8,
            ),
            decoration: ShapeDecoration(color: c.surface, shape: cruShape(28)),
            child: SingleChildScrollView(
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
                  const SizedBox(height: CruSpace.s12),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s16,
                    ),
                    child: Text(
                      'STATUS',
                      style: MobileType.caption.w600.tint(c.label3),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s6),
                  for (final sf in statusOptions)
                    CruPressable(
                      onTap: () {
                        MobileHaptics.select();
                        Navigator.of(sheetContext).pop();
                        setState(() => _statusFilter = sf);
                      },
                      semanticLabel: sf.label,
                      builder: (context, hovered) {
                        final selected = _statusFilter == sf;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: CruSpace.s8,
                            vertical: CruSpace.s2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: CruSpace.s12,
                            vertical: CruSpace.s10,
                          ),
                          decoration: ShapeDecoration(
                            color: selected
                                ? c.accentTint
                                : (hovered ? c.hoverFill : c.surface),
                            shape: cruShape(CruRadius.control),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sf.label,
                                  style:
                                      (selected
                                              ? MobileType.row.w600
                                              : MobileType.row)
                                          .tint(
                                            selected ? c.accentText : c.label,
                                          ),
                                ),
                              ),
                              if (selected)
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
                  const CruSeparator(),
                  const SizedBox(height: CruSpace.s12),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s16,
                    ),
                    child: Text(
                      'TIME',
                      style: MobileType.caption.w600.tint(c.label3),
                    ),
                  ),
                  const SizedBox(height: CruSpace.s6),
                  for (final tf in TaskTimeFilter.values)
                    CruPressable(
                      onTap: () {
                        MobileHaptics.select();
                        Navigator.of(sheetContext).pop();
                        setState(() => _timeFilter = tf);
                      },
                      semanticLabel: tf.label,
                      builder: (context, hovered) {
                        final selected = _timeFilter == tf;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: CruSpace.s8,
                            vertical: CruSpace.s2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: CruSpace.s12,
                            vertical: CruSpace.s10,
                          ),
                          decoration: ShapeDecoration(
                            color: selected
                                ? c.accentTint
                                : (hovered ? c.hoverFill : c.surface),
                            shape: cruShape(CruRadius.control),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tf.label,
                                  style:
                                      (selected
                                              ? MobileType.row.w600
                                              : MobileType.row)
                                          .tint(
                                            selected ? c.accentText : c.label,
                                          ),
                                ),
                              ),
                              if (selected)
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens a lab case to view or move it to its next stage.
  void _openLabCase(BuildContext context, LabCase lc) => showDialog<void>(
    context: mobileRoot(context),
    builder: (_) => LabCaseEditDialog(initialCase: lc),
  );

  void _handleTaskTap(BuildContext context, TaskItem t) {
    final lc = t.labCase;
    if (lc != null) {
      _openLabCase(context, lc);
      return;
    }
    if (t.stage.isFinished) {
      if (t.study != null) {
        openRadReport(context, t.study!);
      } else if (t.patient != null) {
        showTreatmentPlanDialog(mobileRoot(context), patient: t.patient!);
      }
      return;
    }

    switch (t.stage) {
      case TaskStage.toRead:
      case TaskStage.reading:
        if (t.study != null) {
          openRadStudy(context, ref, t.study!);
        }
      case TaskStage.drafting:
      case TaskStage.toSign:
      case TaskStage.toSend:
        if (t.study != null) {
          openRadReport(context, t.study!);
        }
      case TaskStage.awaitingOk:
      case TaskStage.toTreat:
        if (t.patient != null) {
          showTreatmentPlanDialog(
            mobileRoot(context),
            patient: t.patient!,
          ).then((_) {
            ref.invalidate(clinicTreatmentPlansProvider);
          });
        }
      case TaskStage.delivered:
      case TaskStage.invoiced:
      case TaskStage.declined:
      // Lab cases open above, before this switch.
      case TaskStage.labToSend:
      case TaskStage.atLab:
      case TaskStage.labRemake:
      case TaskStage.readyToFit:
      case TaskStage.fitted:
        break;
    }
  }

  void _openPrioritySheet(BuildContext context, RadStudy study) {
    showMobileActionSheet(
      context,
      title: 'Set priority',
      subtitle: study.patientName,
      actions: [
        for (final p in [
          RadPriority.routine,
          RadPriority.urgent,
          RadPriority.stat,
        ])
          MobileSheetAction(
            label: p.label,
            icon: study.priority == p ? CruIcons.check : CruIcons.calendar,
            tone: switch (p) {
              RadPriority.routine => MobileTone.slate,
              RadPriority.urgent => MobileTone.amber,
              RadPriority.stat => MobileTone.blue,
            },
            onTap: () async {
              final ctrl = ref.read(radiologyProvider);
              await ctrl.saveStudy(
                study.copyWith(
                  priority: p,
                  dueAt: await ctrl.dueFor(p, study.receivedAt),
                ),
                auditAction: 'Priority ${p.label}',
                detail: study.patientName,
              );
            },
          ),
      ],
    );
  }

  Future<bool> _confirmDecline(BuildContext context, String patientName) async {
    final result = await showDialog<bool>(
      context: mobileRoot(context),
      builder: (ctx) {
        final c = ctx.cru;
        return Dialog(
          backgroundColor: c.surface,
          surfaceTintColor: Colors.transparent,
          shape: cruShape(CruRadius.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: CruSize.dialog),
            child: Padding(
              padding: const EdgeInsets.all(CruSpace.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Decline plan?', style: CruType.headline.tint(c.label)),
                  const SizedBox(height: CruSpace.s8),
                  Text(
                    'Mark proposed procedures for $patientName as declined?',
                    style: CruType.text.tint(c.label2),
                  ),
                  const SizedBox(height: CruSpace.s24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CruButton(
                        label: 'Cancel',
                        kind: CruButtonKind.inset,
                        onPressed: () => Navigator.of(ctx).pop(false),
                      ),
                      const SizedBox(width: CruSpace.s10),
                      CruButton(
                        label: 'Decline',
                        kind: CruButtonKind.secondary,
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  void _openTaskActions(BuildContext context, TaskItem t) {
    final actions = <MobileSheetAction>[];

    if (t.source == TaskSource.scan || t.source == TaskSource.report) {
      final study = t.study;
      if (study != null) {
        actions.add(
          MobileSheetAction(
            label: 'View scans',
            icon: RadIcons.worklist,
            tone: MobileTone.indigo,
            onTap: () => openRadStudy(context, ref, study),
          ),
        );
        actions.add(
          MobileSheetAction(
            label: 'Write report',
            icon: RadIcons.report,
            tone: MobileTone.teal,
            onTap: () => openRadReport(context, study),
          ),
        );
        if (ref.read(radPacsServersProvider).value?.isNotEmpty ?? false) {
          actions.add(
            MobileSheetAction(
              label: 'Send to PACS',
              icon: CruIcons.arrowUp,
              tone: MobileTone.sky,
              onTap: () => sendRadStudyToPacs(context, ref, study),
            ),
          );
        }
        actions.add(
          MobileSheetAction(
            label: 'Set priority',
            icon: CruIcons.settings,
            tone: MobileTone.slate,
            onTap: () => _openPrioritySheet(context, study),
          ),
        );
        if ((study.status == RadStudyStatus.finalised ||
                study.status == RadStudyStatus.delivered) &&
            study.fee != null &&
            !study.invoiced) {
          actions.add(
            MobileSheetAction(
              label: 'Invoice',
              icon: CruIcons.wallet,
              tone: MobileTone.green,
              onTap: () => invoiceRadStudy(context, ref, study),
            ),
          );
        }
      }
    } else if (t.labCase != null) {
      final lc = t.labCase!;
      actions.add(
        MobileSheetAction(
          label: 'Open lab case',
          icon: CruIcons.box,
          tone: MobileTone.sky,
          onTap: () => _openLabCase(context, lc),
        ),
      );
    } else if (t.source == TaskSource.plan) {
      if (t.patient != null) {
        actions.add(
          MobileSheetAction(
            label: 'Open plan',
            icon: DentalIcons.plan,
            tone: MobileTone.blue,
            onTap: () async {
              await showTreatmentPlanDialog(
                mobileRoot(context),
                patient: t.patient!,
              );
              ref.invalidate(clinicTreatmentPlansProvider);
            },
          ),
        );
      }
      if (t.stage == TaskStage.awaitingOk) {
        actions.add(
          MobileSheetAction(
            label: 'Mark accepted',
            icon: CruIcons.check,
            tone: MobileTone.green,
            onTap: () async {
              final repo = ref.read(dentalRepositoryProvider);
              for (final item in t.planItems) {
                await repo.updateTreatmentPlanLineItemStatus(
                  item.id,
                  TreatmentPlanItemStatus.accepted.code,
                );
              }
              ref.invalidate(clinicTreatmentPlansProvider);
              if (context.mounted) {
                mobileSay(context, 'Plan accepted.');
              }
            },
          ),
        );
        actions.add(
          MobileSheetAction(
            label: 'Mark declined',
            icon: CruIcons.close,
            tone: MobileTone.slate,
            destructive: true,
            onTap: () async {
              final confirmed = await _confirmDecline(context, t.patientName);
              if (!confirmed || !context.mounted) return;
              final repo = ref.read(dentalRepositoryProvider);
              for (final item in t.planItems) {
                await repo.updateTreatmentPlanLineItemStatus(
                  item.id,
                  TreatmentPlanItemStatus.declined.code,
                );
              }
              ref.invalidate(clinicTreatmentPlansProvider);
              if (context.mounted) {
                mobileSay(context, 'Plan declined.');
              }
            },
          ),
        );
      }
    }

    if (t.patient != null) {
      actions.add(
        MobileSheetAction(
          label: 'Open patient',
          icon: CruIcons.user,
          tone: MobileTone.blue,
          onTap: () => openMobilePatient(context, t.patient!),
        ),
      );
    }

    showMobileActionSheet(
      context,
      title: t.patientName,
      subtitle: t.stage.label,
      actions: actions,
    );
  }

  String _formatTimeText(TaskItem t, DateTime now) {
    if (t.isOverdue(now)) {
      final diff = now.difference(t.dueAt!);
      if (diff.inHours < 24) {
        final h = diff.inHours.clamp(1, 23);
        return 'Overdue ${h}h';
      }
      final d = diff.inDays.clamp(1, 9999);
      return 'Overdue ${d}d';
    }

    final diff = now.difference(t.since);
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes.clamp(1, 59);
      return '${m}m ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours.clamp(1, 23);
      return '${h}h ago';
    }
    final d = diff.inDays;
    if (d < 30) {
      return '${d.clamp(1, 29)}d ago';
    }
    final mo = (d / 30).floor();
    return '${mo}mo ago';
  }

  Widget _buildTaskRow(BuildContext context, TaskItem t, DateTime now) {
    final c = context.cru;

    final leading = switch (t.source) {
      TaskSource.scan => const MobileIconTile(
        icon: RadIcons.worklist,
        tone: MobileTone.indigo,
      ),
      TaskSource.report => const MobileIconTile(
        icon: RadIcons.report,
        tone: MobileTone.teal,
      ),
      TaskSource.plan => const MobileIconTile(
        icon: DentalIcons.plan,
        tone: MobileTone.blue,
      ),
      TaskSource.lab => const MobileIconTile(
        icon: CruIcons.box,
        tone: MobileTone.sky,
      ),
    };

    final urgency = t.critical
        ? null
        : switch (t.priority) {
            RadPriority.stat => 'STAT',
            RadPriority.urgent => 'Urgent',
            _ => null,
          };
    final subtitle = [
      ?urgency,
      if (t.title.isNotEmpty) t.title,
      if (t.detail != null && t.detail!.isNotEmpty) t.detail!,
      _formatTimeText(t, now),
    ].join(' · ');
    final study = t.study;
    final bytes = study == null
        ? null
        : ref.watch(_studyBytesProvider(study.id)).value;

    final Widget pillWidget;
    if (t.critical) {
      pillWidget = Container(
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: CruSpace.s10),
        decoration: ShapeDecoration(
          color: c.redTint,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Critical',
              style: MobileType.micro.w600.tabular.tint(c.redText),
            ),
          ],
        ),
      );
    } else if (t.stage.isFinished) {
      final tone = switch (t.stage) {
        TaskStage.delivered => MobileTone.green,
        TaskStage.invoiced => MobileTone.green,
        TaskStage.declined => MobileTone.slate,
        TaskStage.fitted => MobileTone.green,
        _ => MobileTone.slate,
      };
      pillWidget = MobilePill(t.stage.label, tone: tone);
    } else {
      final tone = switch (t.stage) {
        TaskStage.toRead => MobileTone.amber,
        TaskStage.reading => MobileTone.blue,
        TaskStage.drafting => MobileTone.slate,
        TaskStage.toSign => MobileTone.amber,
        TaskStage.toSend => MobileTone.green,
        TaskStage.awaitingOk => MobileTone.amber,
        TaskStage.toTreat => MobileTone.blue,
        TaskStage.labToSend => MobileTone.amber,
        TaskStage.atLab => MobileTone.blue,
        TaskStage.labRemake => MobileTone.amber,
        TaskStage.readyToFit => MobileTone.amber,
        _ => MobileTone.slate,
      };
      pillWidget = MobilePill(t.stage.label, tone: tone);
    }

    final trailing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        pillWidget,
        if (bytes != null) ...[
          const SizedBox(height: CruSpace.s2),
          Text(
            _fileSize(bytes),
            style: MobileType.caption.tabular.tint(c.label3),
          ),
        ],
      ],
    );

    return MobileRow(
      leading: leading,
      title: t.patientName,
      subtitle: subtitle,
      trailing: trailing,
      onTap: () => _handleTaskTap(context, t),
      onLongPress: () => _openTaskActions(context, t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final tabs = {
      for (final t in sidebarTabs(
        dental: ref.watch(dentalFeaturesProvider),
        access: ref.watch(clinicAccessProvider).value,
      ))
        t.tab,
    };
    final worklistOn = tabs.contains(DesktopTab.worklist);
    final reportsOn = tabs.contains(DesktopTab.reports);
    final plansOn = tabs.contains(DesktopTab.treatmentPlans);

    final labOn = tabs.contains(DesktopTab.labCases);

    final radiologyOn = worklistOn || reportsOn;
    final dentalOn = plansOn;
    // Watching keeps the scanner receiver listening while Tasks is open,
    // and has the PACS list ready for "Send to PACS".
    final received = worklistOn
        ? ref.watch(radReceiverProvider).received
        : const <String>[];
    final lastFrom = worklistOn ? ref.watch(radReceiverProvider).lastFrom : '';
    if (worklistOn) ref.watch(radPacsServersProvider);

    final none = !radiologyOn && !dentalOn && !labOn;

    final availableSources = <TaskSourceFilter>[
      TaskSourceFilter.all,
      if (worklistOn) TaskSourceFilter.worklist,
      if (reportsOn) TaskSourceFilter.reports,
      if (plansOn) TaskSourceFilter.plans,
      if (labOn) TaskSourceFilter.labCases,
    ];

    // With one source there are no pills: it is the only filter.
    final effectiveSource = availableSources.length == 2
        ? availableSources[1]
        : (availableSources.contains(_sourceFilter)
              ? _sourceFilter
              : TaskSourceFilter.all);

    final studiesAsync = radiologyOn ? ref.watch(radStudiesProvider) : null;
    final referrers = radiologyOn
        ? ref.watch(radReferrerByIdProvider)
        : const <String, RadReferrer>{};

    final planItemsAsync = dentalOn
        ? ref.watch(clinicTreatmentPlansProvider)
        : null;
    final labCases = labOn ? ref.watch(allLabCasesProvider) : null;
    final patientsAsync = (radiologyOn || dentalOn || labOn)
        ? ref.watch(patientsStreamProvider)
        : null;

    final isLoading =
        (radiologyOn && studiesAsync?.value == null) ||
        (dentalOn &&
            (planItemsAsync?.value == null || patientsAsync?.value == null));

    final patients = patientsAsync?.value ?? const <Patient>[];
    final patientsById = {for (final p in patients) p.id: p};

    final board = buildTaskBoard(
      studies: studiesAsync?.value,
      referrers: referrers,
      planItems: planItemsAsync?.value,
      patientsById: patientsById,
      now: now,
      labCases: labCases,
    );

    final hasAddActions = radiologyOn || dentalOn;

    // Counts for source pills
    int countForSource(TaskSourceFilter s) => switch (s) {
      TaskSourceFilter.all => board.items.length,
      TaskSourceFilter.worklist =>
        board.items
            .where(
              (t) =>
                  t.stage == TaskStage.toRead || t.stage == TaskStage.reading,
            )
            .length,
      TaskSourceFilter.reports =>
        board.items
            .where(
              (t) =>
                  t.stage == TaskStage.drafting ||
                  t.stage == TaskStage.toSign ||
                  t.stage == TaskStage.toSend,
            )
            .length,
      TaskSourceFilter.plans =>
        board.items
            .where(
              (t) =>
                  t.stage == TaskStage.awaitingOk ||
                  t.stage == TaskStage.toTreat,
            )
            .length,
      TaskSourceFilter.labCases =>
        board.items.where((t) => t.source == TaskSource.lab).length,
    };

    // One source's page: its recent strip, search and list. Picking a
    // source clears the status filter, so the page beside uses none.
    Widget page(TaskSourceFilter source) {
      final statusFilter = source == effectiveSource
          ? _statusFilter
          : TaskStatusFilter.any;
      // Filter candidate list: finished items only when explicitly requested
      final bool showingFinished =
          statusFilter == TaskStatusFilter.sent ||
          statusFilter == TaskStatusFilter.invoiced ||
          statusFilter == TaskStatusFilter.declined ||
          statusFilter == TaskStatusFilter.fitted;

      final candidates = showingFinished ? board.finished : board.items;

      final filtered = candidates
          .where((t) => matchesSource(t, source))
          .where((t) => matchesStatus(t, statusFilter))
          .where((t) => matchesTime(t, _timeFilter, now))
          .where((t) => matchesSearch(t, _query))
          .toList();

      if (showingFinished) {
        filtered.sort((a, b) => b.since.compareTo(a.since));
      } else {
        filtered.sort((a, b) => compareUrgency(a, b, now));
      }

      // Recent activity for the sliding strip above search: every task,
      // open or finished, newest change first.
      final recentActivity =
          [
              ...board.items,
              ...board.finished,
            ].where((t) => matchesSource(t, source)).toList()
            ..sort((a, b) => b.since.compareTo(a.since));
      if (recentActivity.length > 10) {
        recentActivity.removeRange(10, recentActivity.length);
      }

      final hasActiveFilter =
          statusFilter != TaskStatusFilter.any ||
          _timeFilter != TaskTimeFilter.any;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 2. Recent activity, as a sliding strip
          _RecentActivityStrip(
            items: recentActivity,
            now: now,
            thumbs: _thumbs,
            onTap: (t) => _handleTaskTap(context, t),
            onLongPress: (t) => _openTaskActions(context, t),
          ),
          const SizedBox(height: CruSpace.s16),

          // 3. Search bar with filter icon: the same on every source, so it
          // stays put while they slide (the dot follows the open source).
          SwipePinned(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MobileMetrics.gutter,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: MobileSearchField(
                      controller: _search,
                      hint: 'Search patient, scan, procedure or referrer',
                      onChanged: (q) => setState(() => _query = q),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s10),
                  _FilterIconButton(
                    hasActiveFilter:
                        _statusFilter != TaskStatusFilter.any ||
                        _timeFilter != TaskTimeFilter.any,
                    onTap: () => _openFilterModal(context, effectiveSource),
                  ),
                ],
              ),
            ),
          ),

          // Active filter removable chips
          if (hasActiveFilter) ...[
            const SizedBox(height: CruSpace.s8),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MobileMetrics.gutter,
              ),
              child: Wrap(
                spacing: CruSpace.s8,
                runSpacing: CruSpace.s6,
                children: [
                  if (statusFilter != TaskStatusFilter.any)
                    _RemovableFilterChip(
                      label: 'Status: ${statusFilter.label}',
                      onRemove: () =>
                          setState(() => _statusFilter = TaskStatusFilter.any),
                    ),
                  if (_timeFilter != TaskTimeFilter.any)
                    _RemovableFilterChip(
                      label: 'Time: ${_timeFilter.label}',
                      onRemove: () =>
                          setState(() => _timeFilter = TaskTimeFilter.any),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CruSpace.s16),

          // 4. One flat list of tasks
          if (board.items.isEmpty && board.finished.isEmpty)
            const MobileEmpty(
              icon: CruIcons.check,
              title: 'All caught up',
              body: 'Nothing is waiting on you right now.',
            )
          else if (filtered.isEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MobileEmpty(
                  icon: CruIcons.search,
                  title: 'No matches',
                  body: 'Try another filter or search.',
                ),
                const SizedBox(height: CruSpace.s8),
                CruPressable(
                  onTap: () {
                    MobileHaptics.tap();
                    setState(() {
                      _statusFilter = TaskStatusFilter.any;
                      _timeFilter = TaskTimeFilter.any;
                      _search.clear();
                      _query = '';
                    });
                  },
                  semanticLabel: 'Clear filters',
                  builder: (context, _) => Text(
                    'Clear filters',
                    style: MobileType.subhead.w600.tint(context.cru.accentText),
                  ),
                ),
                const SizedBox(height: CruSpace.s16),
              ],
            )
          else
            MobileRowGroup(
              children: [
                for (final t in filtered) _buildTaskRow(context, t, now),
              ],
            ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.only(bottom: MobileMetrics.bottom(context)),
      children: [
        MobileHeader(
          title: 'Tasks',
          trailing: hasAddActions
              ? MobileCircleButton(
                  icon: CruIcons.plus,
                  semanticLabel: 'Add',
                  onPressed: () => _openAddSheet(
                    context,
                    radiology: radiologyOn,
                    dental: dentalOn,
                  ),
                )
              : null,
        ),
        const SizedBox(height: CruSpace.s16),
        if (received.isNotEmpty) ...[
          MobileRowGroup(
            children: [
              MobileRow(
                leading: const MobileIconTile(
                  icon: RadIcons.import,
                  tone: MobileTone.blue,
                ),
                title: '${RadFormat.images(received.length)} received',
                subtitle: lastFrom.isEmpty ? 'From scanners' : 'From $lastFrom',
                trailing: MobilePill('Add to worklist', tone: MobileTone.blue),
                onTap: () => importRadReceived(context, ref),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
        ],
        if (none)
          const MobileEmpty(
            icon: CruIcons.check,
            title: 'No tasks here yet',
            body:
                'Scans to report and treatment plans show up here once radiology or dental features are on.',
          )
        else if (isLoading)
          const MobileRowGroup(
            children: [MobileLoading('Loading your tasks…', height: 160)],
          )
        else ...[
          // 1. Source filter pill row (shown only when > 1 source is available)
          if (availableSources.length > 2) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: MobileMetrics.gutter,
              ),
              child: Row(
                children: [
                  for (final s in availableSources) ...[
                    MobileChip(
                      label: s.label,
                      count: countForSource(s),
                      selected: effectiveSource == s,
                      onTap: () {
                        setState(() {
                          _sourceFilter = s;
                          _statusFilter = TaskStatusFilter.any;
                        });
                      },
                    ),
                    const SizedBox(width: CruSpace.s8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: CruSpace.s12),
          ],

          // Each source's page side by side: drag sideways to switch.
          SwipePages<TaskSourceFilter>(
            values: availableSources.length > 2
                ? availableSources
                : [effectiveSource],
            value: effectiveSource,
            onChanged: (s) => setState(() {
              _sourceFilter = s;
              _statusFilter = TaskStatusFilter.any;
            }),
            builder: (context, source) => page(source),
          ),
        ],
      ],
    );
  }
}

/// A swipeable strip of the most recently changed tasks, laid out like the
/// Material 3 "multi-browse" carousel (Google Files / Photos "Recent"): a
/// large card, a medium one and a narrow sliver that grow and shrink as
/// they slide. Card content keeps its full size and is revealed through
/// the card like a window, so nothing squashes while it moves.
class _RecentActivityStrip extends StatelessWidget {
  const _RecentActivityStrip({
    required this.items,
    required this.now,
    required this.thumbs,
    required this.onTap,
    required this.onLongPress,
  });

  final List<TaskItem> items;
  final DateTime now;
  final RadThumbCache thumbs;
  final ValueChanged<TaskItem> onTap;
  final ValueChanged<TaskItem> onLongPress;

  static const double _height = 184;
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    // Fewer weights when there are only one or two tasks, so a lone card
    // isn't left half-width next to empty space.
    final weights = switch (items.length) {
      1 => const [1],
      2 => const [3, 2],
      _ => const [3, 2, 1],
    };
    final totalWeight = weights.fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MobileMetrics.gutter + 2,
            0,
            MobileMetrics.gutter,
            CruSpace.s8,
          ),
          child: Text(
            'Recent activity',
            style: MobileType.groupLabel.tint(mobileInk(context)),
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MobileMetrics.gutter,
            ),
            child: MobileCard(
              padding: const EdgeInsets.all(CruSpace.s12),
              child: Row(
                children: [
                  const MobileIconTile(
                    icon: CruIcons.check,
                    tone: MobileTone.green,
                  ),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(
                      'New and updated tasks will show up here.',
                      style: MobileType.subhead.tint(c.label2),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: _height,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MobileMetrics.gutter - _gap,
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  // Width of the largest card: the size content is laid
                  // out at, whatever width the card has at the moment.
                  final fullWidth =
                      box.maxWidth * weights.first / totalWeight - _gap * 2;
                  return CarouselView.weighted(
                    flexWeights: weights,
                    itemSnapping: true,
                    enableSplash: false,
                    padding: const EdgeInsets.symmetric(horizontal: _gap),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    itemClipBehavior: Clip.antiAlias,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    children: [
                      for (final t in items)
                        _RecentActivityCard(
                          task: t,
                          now: now,
                          thumbs: thumbs,
                          fullWidth: fullWidth,
                          onTap: () => onTap(t),
                          onLongPress: () => onLongPress(t),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({
    required this.task,
    required this.now,
    required this.thumbs,
    required this.fullWidth,
    required this.onTap,
    required this.onLongPress,
  });

  final TaskItem task;
  final DateTime now;
  final RadThumbCache thumbs;
  final double fullWidth;

  /// The scan's first picture, once its thumbnail is ready; null for plans,
  /// scans without a readable picture, or while it's still being made.
  ui.Image? _thumb() {
    final s = task.study;
    if (s == null) return null;
    for (final i in s.images) {
      if (i.compressed) continue;
      thumbs.request(s, i);
      return thumbs.image(s.id, i.id);
    }
    return null;
  }

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static String _ago(DateTime since, DateTime now) {
    final diff = now.difference(since);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  /// Bright status dot, readable on the blue card in both appearances.
  static Color _statusDot(TaskItem t) {
    if (t.critical) return const Color(0xFFFF6B6B);
    return switch (t.stage) {
      TaskStage.toRead ||
      TaskStage.toSign ||
      TaskStage.awaitingOk ||
      TaskStage.labToSend ||
      TaskStage.labRemake ||
      TaskStage.readyToFit => const Color(0xFFFFB340),
      TaskStage.reading ||
      TaskStage.toTreat ||
      TaskStage.atLab => const Color(0xFF93C5FD),
      TaskStage.toSend ||
      TaskStage.delivered ||
      TaskStage.invoiced ||
      TaskStage.fitted => const Color(0xFF4ADE80),
      TaskStage.drafting || TaskStage.declined => const Color(0xFFCBD5E1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = task;

    // The card looks like the work it's at now (a scan becomes a report
    // card once reading is done), not where the task started.
    final (icon, top, bottom) = switch (t.stage.source) {
      TaskSource.scan => (
        RadIcons.worklist,
        const Color(0xFF3960FB),
        const Color(0xFF1E3A8A),
      ),
      TaskSource.report => (
        RadIcons.report,
        const Color(0xFF4F46E5),
        const Color(0xFF1E1B4B),
      ),
      TaskSource.plan => (
        DentalIcons.plan,
        const Color(0xFF2563EB),
        const Color(0xFF0C4A6E),
      ),
      TaskSource.lab => (
        CruIcons.box,
        const Color(0xFF1D4ED8),
        const Color(0xFF172554),
      ),
    };

    final subtitle = [
      if (t.title.isNotEmpty) t.title,
      if (t.detail != null && t.detail!.isNotEmpty) t.detail!,
    ].join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        MobileHaptics.tap();
        onTap();
      },
      onLongPress: () {
        MobileHaptics.tap();
        onLongPress();
      },
      child: ListenableBuilder(
        listenable: thumbs,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final thumb = _thumb();
            // Text fades out as the card narrows into the sliver at the edge.
            final reveal = ((box.maxWidth - 80) / (fullWidth * 0.7 - 80)).clamp(
              0.0,
              1.0,
            );

            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [top, bottom],
                ),
              ),
              child: OverflowBox(
                minWidth: fullWidth,
                maxWidth: fullWidth,
                alignment: Alignment.center,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The scan itself when there's a picture; otherwise a
                    // large faint glyph on the blue card.
                    if (thumb != null)
                      RawImage(image: thumb, fit: BoxFit.cover)
                    else
                      Positioned(
                        right: -18,
                        top: 28,
                        child: CruIcon(
                          icon,
                          size: 120,
                          strokeWidth: 1.4,
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                    // Scrim so the bottom text stays readable.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x59000000)],
                        ),
                      ),
                    ),
                    // Centred glyph for the narrow sliver; fades as text appears.
                    Align(
                      alignment: const Alignment(0, -0.2),
                      child: Opacity(opacity: 1 - reveal, child: _glyph(icon)),
                    ),
                    Opacity(
                      opacity: reveal,
                      child: Padding(
                        padding: const EdgeInsets.all(CruSpace.s12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _glyph(icon, size: 32),
                                const Spacer(),
                                Text(
                                  _ago(t.since, now),
                                  style: MobileType.micro.w600.tabular.tint(
                                    Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              t.patientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MobileType.row.w600.tint(Colors.white),
                            ),
                            const SizedBox(height: CruSpace.s2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MobileType.caption.tint(
                                Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: CruSpace.s8),
                            _statusPill(t),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _glyph(CruIconData icon, {double size = 44}) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      shape: BoxShape.circle,
    ),
    child: CruIcon(
      icon,
      size: size * 0.48,
      strokeWidth: 1.9,
      color: Colors.white,
    ),
  );

  Widget _statusPill(TaskItem t) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: CruSpace.s8),
    decoration: ShapeDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const StadiumBorder(),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: _statusDot(t),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: CruSpace.s6),
        Flexible(
          child: Text(
            t.critical ? 'Critical · ${t.stage.label}' : t.stage.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MobileType.micro.w600.tint(Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({required this.hasActiveFilter, required this.onTap});

  final bool hasActiveFilter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;

    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Filter tasks',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        height: 48,
        width: 48,
        decoration: ShapeDecoration(
          color: hasActiveFilter
              ? c.accentTint
              : (hovered ? c.hoverFill : c.surface),
          shape: cruShape(
            CruRadius.control + 2,
            side: BorderSide(
              color: hasActiveFilter
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
              color: hasActiveFilter ? c.accentText : c.label2,
            ),
            if (hasActiveFilter)
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

class _RemovableFilterChip extends StatelessWidget {
  const _RemovableFilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onRemove,
      semanticLabel: 'Remove $label filter',
      builder: (context, _) => Container(
        height: 28,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: ShapeDecoration(
          color: c.accentTint,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: MobileType.caption.w600.tint(c.accentText)),
            const SizedBox(width: 4),
            CruIcon(CruIcons.close, size: 14, color: c.accentText),
          ],
        ),
      ),
    );
  }
}
