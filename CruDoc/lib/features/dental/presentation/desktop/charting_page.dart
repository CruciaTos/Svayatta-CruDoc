import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:doctor_management_app/features/appointments/data/providers/appointments_providers.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_builder.dart';
import 'package:doctor_management_app/features/appointments/domain/appointments_models.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/charting_screen.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The patient the sidebar's Charting page shows. Kept while you visit
/// other pages and come back.
final chartingPatientIdProvider = StateProvider<String?>((ref) => null);

/// A patient's Charting inside the shell (the sidebar stays), opened from
/// a patient's chart button on the Patients screen. The search on top
/// switches patient. It has no empty page: with no patient picked it goes
/// back to Patients.
class ChartingPage extends ConsumerWidget {
  const ChartingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600
        ? CruSpace.mainPaddingPhone
        : width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;
    final now = ref.watch(apptsNowProvider);
    final day = ref.watch(apptDayItemsProvider(ApptsBuilder.dateOnly(now)));
    final items = day.value ?? const <ApptItem>[];
    final patientsAsync = ref.watch(patientsStreamProvider);
    final patientsLoaded = patientsAsync.hasValue;
    final patients = patientsAsync.value ?? const [];
    final chosen = ref.watch(chartingPatientIdProvider);

    Patient? patient;
    if (chosen != null) {
      for (final p in patients) {
        if (p.id == chosen) {
          patient = p;
          break;
        }
      }
    }

    final picker = _PatientSearch(
      items: items,
      patients: patients,
      current: patient,
      onPick: (p) => ref.read(chartingPatientIdProvider.notifier).state = p.id,
    );

    // No patient picked (or theirs is gone): Charting has no page of its
    // own; patients are picked on the Patients screen, so go there.
    if (patient == null) {
      if (chosen == null || patientsLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(shellNavigatorProvider)?.call(DesktopTab.patients);
        });
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: padding,
      child: ChartingScreen(
        key: ValueKey(patient.id),
        patient: patient,
        embedded: true,
        picker: picker,
      ),
    );
  }
}

/// One patient in the dropdown, with its line ("Today 10:30 AM · Crown
/// 46", or age and sex).
class _Option {
  const _Option(this.patient, this.line);
  final Patient patient;
  final String line;
}

/// The search bar on top of Charting: type a name or phone, pick from the
/// dropdown (arrow keys and Enter work). Empty, it lists today's patients
/// then recent ones.
class _PatientSearch extends StatefulWidget {
  const _PatientSearch({
    required this.items,
    required this.patients,
    required this.current,
    required this.onPick,
  });

  final List<ApptItem> items;
  final List<Patient> patients;
  final Patient? current;
  final ValueChanged<Patient> onPick;

  @override
  State<_PatientSearch> createState() => _PatientSearchState();
}

class _PatientSearchState extends State<_PatientSearch> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'charting patient search');

  static const int _recent = 5;
  static const int _matches = 12;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Option> _options(String text) {
    // Today's patients in appointment order, each once.
    final today = <String, _Option>{};
    final sorted = [
      ...widget.items,
    ]..sort((a, b) => a.visit.scheduledStart.compareTo(b.visit.scheduledStart));
    for (final item in sorted) {
      for (final m in item.members.isEmpty ? [item] : item.members) {
        final p = m.patient;
        if (p == null || today.containsKey(p.id)) continue;
        final reason = m.reason?.trim() ?? '';
        today[p.id] = _Option(
          p,
          'Today ${DashFormat.time(m.visit.scheduledStart)}'
          '${reason.isEmpty ? '' : ' · $reason'}',
        );
      }
    }
    _Option plain(Patient p) =>
        today[p.id] ?? _Option(p, PatientFormat.ageSexLong(p));

    final q = text.trim().toLowerCase();
    if (q.isEmpty) {
      final recent = ([
        ...widget.patients.where(
          (p) => !today.containsKey(p.id) && p.id != widget.current?.id,
        ),
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt))).take(_recent);
      return [...today.values, for (final p in recent) plain(p)];
    }
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return [
      for (final p in widget.patients)
        if (p.fullName.toLowerCase().contains(q) ||
            (digits.length >= 3 &&
                p.phone.replaceAll(RegExp(r'\D'), '').contains(digits)))
          plain(p),
    ].take(_matches).toList();
  }

  void _pick(_Option o) {
    widget.onPick(o.patient);
    _controller.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return LayoutBuilder(
      builder: (context, box) => RawAutocomplete<_Option>(
        textEditingController: _controller,
        focusNode: _focus,
        optionsBuilder: (v) => _options(v.text),
        displayStringForOption: (o) => o.patient.fullName,
        onSelected: _pick,
        fieldViewBuilder: (context, controller, focus, submit) => _SearchField(
          controller: controller,
          focus: focus,
          hint: widget.current == null
              ? 'Search patients by name or phone'
              : 'Switch patient',
          onSubmitted: submit,
        ),
        optionsViewBuilder: (context, onSelected, options) {
          final list = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: CruSpace.s6),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  width: box.maxWidth,
                  constraints: const BoxConstraints(maxHeight: 380),
                  decoration: ShapeDecoration(
                    color: c.surface,
                    shape: cruShape(
                      CruRadius.control,
                      side: BorderSide(color: c.separator),
                    ),
                    shadows: [
                      BoxShadow(
                        color: c.label.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(CruSpace.s6),
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, i) => _OptionRow(
                      option: list[i],
                      highlighted:
                          AutocompleteHighlightedOption.of(context) == i,
                      onTap: () => onSelected(list[i]),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The search bar itself: inset fill, search icon, no label.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return ListenableBuilder(
      listenable: focus,
      builder: (context, _) {
        final focused = focus.hasFocus;
        return AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          constraints: const BoxConstraints(minHeight: CruSize.actionButton),
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: focused ? c.surface : c.inset,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(
                color: focused ? c.separator : c.separator.withValues(alpha: 0),
              ),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              CruIcon(
                CruIcons.search,
                size: 17,
                strokeWidth: 2,
                color: c.label3,
              ),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  cursorColor: c.accent,
                  style: CruType.input.tint(c.label),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSubmitted(),
                  decoration: InputDecoration.collapsed(
                    hintText: hint,
                    hintStyle: CruType.input.tint(c.label3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A dropdown row: monogram, name and its line; lit when highlighted by
/// the arrow keys or hovered.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.highlighted,
    required this.onTap,
  });

  final _Option option;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = option.patient;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: 'Chart ${p.fullName}',
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s10,
          vertical: CruSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: highlighted || hovered
              ? c.hoverFill
              : c.hoverFill.withValues(alpha: 0),
          shape: cruShape(CruRadius.control - CruSpace.s6),
        ),
        child: Row(
          children: [
            CruMonogram(name: p.fullName, size: CruSize.monogramRow),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.fullName,
                    style: CruType.callout.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    option.line,
                    style: CruType.subhead.tabular.tint(c.label2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
