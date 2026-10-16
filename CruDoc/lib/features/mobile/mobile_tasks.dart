import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/data/models/treatment_plan_line_item_model.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_dialogs.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_icons.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_desktop_providers.dart';
import 'package:doctor_management_app/features/dental/presentation/providers/dental_providers.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/mobile/tasks/tasks_logic.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/open_study.dart';
import 'package:doctor_management_app/features/radiology/presentation/rad_import_flow.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_dialogs.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/phrase_library.dart';
import 'package:doctor_management_app/features/radiology/presentation/reports/template_manager.dart';
import 'package:doctor_management_app/features/radiology/presentation/rvg_capture_dialog.dart';
import 'package:doctor_management_app/features/shell/components/cru_sidebar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Rebuilt Tasks tab for the mobile shell: one unified to-do list with
/// source pill filter, 4 glance boxes, search with filter icon, and flat list.
class MobileTasksScreen extends ConsumerStatefulWidget {
  const MobileTasksScreen({super.key, required this.enabledModules});

  final List<String> enabledModules;

  @override
  ConsumerState<MobileTasksScreen> createState() => _MobileTasksScreenState();
}

class _MobileTasksScreenState extends ConsumerState<MobileTasksScreen> {
  TaskSourceFilter _sourceFilter = TaskSourceFilter.all;
  TaskStatusFilter _statusFilter = TaskStatusFilter.any;
  TaskTimeFilter _timeFilter = TaskTimeFilter.any;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
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
    showMobileActionSheet(
      context,
      title: 'New task',
      actions: actions,
    );
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
            decoration: ShapeDecoration(
              color: c.surface,
              shape: cruShape(28),
            ),
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
                    padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
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
                                  style: (selected
                                          ? MobileType.row.w600
                                          : MobileType.row)
                                      .tint(selected ? c.accentText : c.label),
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
                    padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
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
                                  style: (selected
                                          ? MobileType.row.w600
                                          : MobileType.row)
                                      .tint(selected ? c.accentText : c.label),
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

  void _handleTaskTap(BuildContext context, TaskItem t) {
    if (t.stage.isFinished) {
      if (t.study != null) {
        openRadReport(context, t.study!);
      } else if (t.patient != null) {
        showTreatmentPlanDialog(
          mobileRoot(context),
          patient: t.patient!,
        );
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
      subtitle: t.stage.isFinished
          ? t.stage.label
          : '${t.stage.label} · Step ${t.stage.step} of ${t.stage.steps}',
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

    if (t.dueAt != null) {
      final due = t.dueAt!;
      if (due.year == now.year && due.month == now.month && due.day == now.day) {
        return 'Due ${DashFormat.time(due)}';
      }
      return 'Due ${DashFormat.shortDate(due)}';
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

  Widget _buildTaskRow(
    BuildContext context,
    TaskItem t,
    DateTime now,
  ) {
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
    };

    String prefix = '';
    if (!t.critical) {
      if (t.priority == RadPriority.stat) {
        prefix = 'STAT · ';
      } else if (t.priority == RadPriority.urgent) {
        prefix = 'Urgent · ';
      }
    }
    final timeStr = _formatTimeText(t, now);
    final subtitle = [
      '$prefix${t.title}',
      if (t.detail != null && t.detail!.isNotEmpty) t.detail!,
      timeStr,
    ].join(' · ');

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
        _ => MobileTone.slate,
      };
      pillWidget = MobilePill(t.stage.label, tone: tone);
    }

    final trailing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        pillWidget,
        if (!t.stage.isFinished) ...[
          const SizedBox(height: CruSpace.s2),
          Text(
            'Step ${t.stage.step} of ${t.stage.steps}',
            style: MobileType.caption.tint(c.label3),
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

  Widget _buildGlanceSection(BuildContext context, List<_GlanceData> tiles) {
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 360;

    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _GlanceTile(data: tiles[0])),
                const SizedBox(width: CruSpace.s8),
                Expanded(child: _GlanceTile(data: tiles[1])),
              ],
            ),
            const SizedBox(height: CruSpace.s8),
            Row(
              children: [
                Expanded(child: _GlanceTile(data: tiles[2])),
                const SizedBox(width: CruSpace.s8),
                Expanded(child: _GlanceTile(data: tiles[3])),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      child: Row(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: CruSpace.s6),
            Expanded(child: _GlanceTile(data: tiles[i])),
          ],
        ],
      ),
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

    final radiologyOn = worklistOn || reportsOn;
    final dentalOn = plansOn;

    final none = !radiologyOn && !dentalOn;

    final availableSources = <TaskSourceFilter>[
      TaskSourceFilter.all,
      if (worklistOn) TaskSourceFilter.worklist,
      if (reportsOn) TaskSourceFilter.reports,
      if (plansOn) TaskSourceFilter.plans,
    ];
    final activeCount = (worklistOn ? 1 : 0) + (reportsOn ? 1 : 0) + (plansOn ? 1 : 0);

    final effectiveSource = activeCount == 1
        ? (worklistOn
            ? TaskSourceFilter.worklist
            : (reportsOn ? TaskSourceFilter.reports : TaskSourceFilter.plans))
        : (availableSources.contains(_sourceFilter)
            ? _sourceFilter
            : TaskSourceFilter.all);

    final studiesAsync = radiologyOn ? ref.watch(radStudiesProvider) : null;
    final referrers = radiologyOn
        ? ref.watch(radReferrerByIdProvider)
        : const <String, RadReferrer>{};

    final reportsAsync = reportsOn ? ref.watch(radReportsProvider) : null;

    final planItemsAsync =
        dentalOn ? ref.watch(clinicTreatmentPlansProvider) : null;
    final patientsAsync =
        (radiologyOn || dentalOn) ? ref.watch(patientsStreamProvider) : null;

    final isLoading = (radiologyOn && studiesAsync?.value == null) ||
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
    );

    final hasAddActions = radiologyOn || dentalOn;

    // Filter candidate list: finished items only when explicitly requested
    final bool showingFinished = _statusFilter == TaskStatusFilter.sent ||
        _statusFilter == TaskStatusFilter.invoiced ||
        _statusFilter == TaskStatusFilter.declined;

    final candidates = showingFinished ? board.finished : board.items;

    final filtered = candidates
        .where((t) => matchesSource(t, effectiveSource))
        .where((t) => matchesStatus(t, _statusFilter))
        .where((t) => matchesTime(t, _timeFilter, now))
        .where((t) => matchesSearch(t, _query))
        .toList();

    if (showingFinished) {
      filtered.sort((a, b) => b.since.compareTo(a.since));
    } else {
      filtered.sort((a, b) => compareUrgency(a, b, now));
    }

    // Counts for source pills
    int countForSource(TaskSourceFilter s) => switch (s) {
          TaskSourceFilter.all => board.items.length,
          TaskSourceFilter.worklist => board.items
              .where((t) =>
                  t.stage == TaskStage.toRead || t.stage == TaskStage.reading)
              .length,
          TaskSourceFilter.reports => board.items
              .where((t) =>
                  t.stage == TaskStage.drafting ||
                  t.stage == TaskStage.toSign ||
                  t.stage == TaskStage.toSend)
              .length,
          TaskSourceFilter.plans => board.items
              .where((t) =>
                  t.stage == TaskStage.awaitingOk ||
                  t.stage == TaskStage.toTreat)
              .length,
        };

    // Glance boxes computation
    final c = context.cru;
    final studies = studiesAsync?.value ?? const <RadStudy>[];
    final reports = reportsAsync?.value ?? const <RadReport>[];
    final planItems =
        planItemsAsync?.value?.where((i) => !i.isDeleted).toList() ??
            const <TreatmentPlanLineItemModel>[];

    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final List<_GlanceData> glanceTiles;
    switch (effectiveSource) {
      case TaskSourceFilter.worklist:
        final toRead = studies
            .where((s) =>
                s.status == RadStudyStatus.newStudy ||
                s.status == RadStudyStatus.reading)
            .toList();
        final urgent =
            studies.where((s) => s.status.isOpen && s.priority != RadPriority.routine).length;
        final overdue =
            studies.where((s) => s.status.isOpen && s.isOverdue(now)).length;
        final signedToday = studies
            .where((s) => !s.status.isOpen && isSameDay(s.updatedAt, now))
            .length;

        glanceTiles = [
          _GlanceData(
            label: 'To read',
            value: '${toRead.length}',
            caption: toRead.isEmpty
                ? 'All caught up'
                : 'Oldest ${RadFormat.ago(toRead.map((s) => s.receivedAt).reduce((a, b) => a.isBefore(b) ? a : b), now).toLowerCase()}',
            onTap: () => setState(() => _statusFilter = TaskStatusFilter.toRead),
          ),
          _GlanceData(
            label: 'Urgent & STAT',
            value: '$urgent',
            caption: urgent == 0 ? 'None waiting' : 'Waiting for a report',
            onTap: () => setState(() => _statusFilter = TaskStatusFilter.urgent),
          ),
          _GlanceData(
            label: 'Overdue',
            value: '$overdue',
            caption: overdue == 0 ? 'On time' : 'Past due time',
            valueColor:
                overdue > 0 ? mobileTone(c, MobileTone.amber).$2 : null,
            onTap: () => setState(() => _timeFilter = TaskTimeFilter.overdue),
          ),
          _GlanceData(
            label: 'Signed today',
            value: '$signedToday',
            caption: 'Reports signed',
          ),
        ];

      case TaskSourceFilter.reports:
        final drafts =
            studies.where((s) => s.status == RadStudyStatus.draft).length;
        final prelim =
            studies.where((s) => s.status == RadStudyStatus.preliminary).length;
        final signedWeek = reports
            .where((r) => r.signedAt != null && !r.signedAt!.isBefore(weekStart))
            .length;
        final sentWeek = reports
            .where((r) => r.sharedAt != null && !r.sharedAt!.isBefore(weekStart))
            .length;

        glanceTiles = [
          _GlanceData(
            label: 'Drafts',
            value: '$drafts',
            caption: drafts == 0 ? 'None half-written' : '$drafts writing',
            onTap: () =>
                setState(() => _statusFilter = TaskStatusFilter.drafting),
          ),
          _GlanceData(
            label: 'Awaiting signature',
            value: '$prelim',
            caption: prelim == 0 ? 'None waiting' : 'Preliminary, not signed',
            onTap: () =>
                setState(() => _statusFilter = TaskStatusFilter.toSign),
          ),
          _GlanceData(
            label: 'Signed this week',
            value: '$signedWeek',
            caption: 'Since Monday',
          ),
          _GlanceData(
            label: 'Sent this week',
            value: '$sentWeek',
            caption: sentWeek == 0 ? 'None sent yet' : '$sentWeek sent in all',
            onTap: () => setState(() => _statusFilter = TaskStatusFilter.sent),
          ),
        ];

      case TaskSourceFilter.plans:
        final proposed = planItems
            .where((i) =>
                TreatmentPlanItemStatus.fromString(i.status) ==
                TreatmentPlanItemStatus.proposed)
            .toList();
        final accepted = planItems
            .where((i) =>
                TreatmentPlanItemStatus.fromString(i.status) ==
                TreatmentPlanItemStatus.accepted)
            .toList();
        final invoiced = planItems
            .where((i) =>
                TreatmentPlanItemStatus.fromString(i.status) ==
                TreatmentPlanItemStatus.invoiced)
            .toList();
        final declined = planItems
            .where((i) =>
                TreatmentPlanItemStatus.fromString(i.status) ==
                TreatmentPlanItemStatus.declined)
            .toList();

        final proposedSum =
            proposed.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);
        final acceptedSum =
            accepted.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);
        final invoicedSum =
            invoiced.fold<double>(0.0, (sum, i) => sum + i.estimatedPrice);

        final decided = accepted.length + invoiced.length + declined.length;
        final acceptance = decided == 0
            ? '—'
            : '${((accepted.length + invoiced.length) * 100 / decided).round()}%';

        glanceTiles = [
          _GlanceData(
            label: 'Awaiting a yes',
            value: DashFormat.rupees(proposedSum),
            caption: proposed.isEmpty
                ? 'Nothing waiting'
                : '${DashFormat.plural(proposed.length, 'procedure')} proposed',
            valueColor:
                proposed.isNotEmpty ? mobileTone(c, MobileTone.amber).$2 : null,
            onTap: () =>
                setState(() => _statusFilter = TaskStatusFilter.awaiting),
          ),
          _GlanceData(
            label: 'Accepted',
            value: DashFormat.rupees(acceptedSum),
            caption: accepted.isEmpty
                ? 'Nothing to do yet'
                : '${DashFormat.plural(accepted.length, 'procedure')} to do',
            onTap: () =>
                setState(() => _statusFilter = TaskStatusFilter.accepted),
          ),
          _GlanceData(
            label: 'Invoiced',
            value: DashFormat.rupees(invoicedSum),
            caption: '${DashFormat.plural(invoiced.length, 'procedure')} done',
            onTap: () =>
                setState(() => _statusFilter = TaskStatusFilter.invoiced),
          ),
          _GlanceData(
            label: 'Acceptance',
            value: acceptance,
            caption: decided == 0 ? 'No decisions yet' : 'of $decided decided',
          ),
        ];

      case TaskSourceFilter.all:
        final openCount = board.items.length;
        final overdueCount =
            board.items.where((t) => t.isOverdue(now)).length;
        final urgentCount = board.items
            .where((t) =>
                t.critical ||
                t.priority == RadPriority.stat ||
                t.priority == RadPriority.urgent)
            .length;
        final doneCount = board.doneToday;

        glanceTiles = [
          _GlanceData(
            label: 'To do',
            value: '$openCount',
            caption: 'Open tasks',
            onTap: () => setState(() => _statusFilter = TaskStatusFilter.open),
          ),
          _GlanceData(
            label: 'Overdue',
            value: '$overdueCount',
            caption: overdueCount == 0 ? 'On time' : 'Past due time',
            valueColor:
                overdueCount > 0 ? mobileTone(c, MobileTone.amber).$2 : null,
            onTap: () => setState(() => _timeFilter = TaskTimeFilter.overdue),
          ),
          _GlanceData(
            label: 'Urgent',
            value: '$urgentCount',
            caption: urgentCount == 0 ? 'None waiting' : 'Needs attention',
            onTap: () => setState(() => _statusFilter = TaskStatusFilter.urgent),
          ),
          _GlanceData(
            label: 'Done today',
            value: '$doneCount',
            caption: 'Finished today',
          ),
        ];
    }

    final hasActiveFilter =
        _statusFilter != TaskStatusFilter.any || _timeFilter != TaskTimeFilter.any;

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
          if (activeCount > 1) ...[
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

          // 2. 4 Glance boxes
          _buildGlanceSection(context, glanceTiles),
          const SizedBox(height: CruSpace.s16),

          // 3. Search bar with filter icon
          Padding(
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
                  hasActiveFilter: hasActiveFilter,
                  onTap: () => _openFilterModal(context, effectiveSource),
                ),
              ],
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
                  if (_statusFilter != TaskStatusFilter.any)
                    _RemovableFilterChip(
                      label: 'Status: ${_statusFilter.label}',
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
                    style:
                        MobileType.subhead.w600.tint(context.cru.accentText),
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
      ],
    );
  }
}

class _GlanceData {
  final String label;
  final String value;
  final String caption;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _GlanceData({
    required this.label,
    required this.value,
    required this.caption,
    this.valueColor,
    this.onTap,
  });
}

class _GlanceTile extends StatelessWidget {
  const _GlanceTile({required this.data});
  final _GlanceData data;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return MobileCard(
      onTap: data.onTap,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MobileType.caption.w500.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: MobileType.metric.copyWith(
                color: data.valueColor ?? c.label,
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s2),
          SizedBox(
            height: 14,
            child: Text(
              data.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MobileType.micro.tabular.tint(c.label3),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.hasActiveFilter,
    required this.onTap,
  });

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
