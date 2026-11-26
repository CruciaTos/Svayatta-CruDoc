import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/layout/device_layout.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/core/providers/specialty_provider.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/specialties/oralmed/oralmed_history.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/mobile/mobile_backdrop.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/mobile/mobile_nav_bar.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/quick_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_top_bar.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/poster_hero.dart';
import 'package:doctor_management_app/features/therapy/presentation/physio_icons.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/goals_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/hep_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/modality_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/muscle_chart_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/outcome_scales_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/physio_photos_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/progress_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/rom_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/screening_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/sessions_card.dart';
import 'package:doctor_management_app/features/therapy/presentation/widgets/special_tests_card.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/swipe_pages.dart';

enum PhysioTab {
  assess('Assess'),
  progress('Progress'),
  treat('Treat'),
  records('Records');

  const PhysioTab(this.label);
  final String label;
}

/// Opens [patient]'s Physio workspace on [tab].
Future<void> openPhysio(
  BuildContext context,
  Patient patient, {
  PhysioTab tab = PhysioTab.assess,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    builder: (_) => Theme(
      data: Theme.of(context),
      child: PhysioScreen(patient: patient, initialTab: tab),
    ),
  ),
);

/// Full-screen physiotherapy workspace (Assess, Progress, Treat, Records),
/// usable from any specialty with clinical view access.
class PhysioScreen extends ConsumerStatefulWidget {
  const PhysioScreen({
    super.key,
    required this.patient,
    this.initialTab = PhysioTab.assess,
    this.embedded = false,
    this.picker,
  });

  final Patient patient;
  final PhysioTab initialTab;

  /// Inside the sidebar's Physio page: no Scaffold or padding of its own.
  final bool embedded;

  /// The patient search beside the title (the sidebar page), in place of
  /// back.
  final Widget? picker;

  @override
  ConsumerState<PhysioScreen> createState() => _PhysioScreenState();
}

class _PhysioScreenState extends ConsumerState<PhysioScreen> {
  late PhysioTab _tab = widget.initialTab;

  void _go(PhysioTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final phone = !usesDesktopLayout(context);
    final p =
        ref.watch(patientSummaryProvider(widget.patient.id)).value?.patient ??
        widget.patient;

    final clinical = ref.watch(
      clinicCanProvider(ClinicPermission.clinicalView),
    );
    final specialty = ref.watch(activeDoctorSpecialtyProvider).value?.type;
    final isDentist = clinical && ref.watch(isDentistProvider);
    final isHomeopath = clinical && specialty == DoctorSpecialtyType.homeopathy;

    final caseSheet = isHomeopath
        ? ref.watch(homeopathyCaseSheetProvider(p.id)).value
        : null;
    final omHistory = isDentist
        ? omHistoryOf(
            ref
                    .watch(
                      patientRecordsProvider((
                        patientId: p.id,
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
          : isDentist
          ? omAllergyText(omHistory)
          : null,
    );

    final allergyPill = allergies == null
        ? null
        : allergies.none
        ? const CruInfoPill(
            text: 'No known allergies',
            icon: CruIcons.check,
            tone: CruInfoPillTone.outlined,
          )
        : CruInfoPill(
            text: 'Allergic to ${allergies.text}',
            icon: CruIcons.warning,
            tone: CruInfoPillTone.allergy,
          );

    final restLabel = widget.picker == null ? 'Back' : 'Patients';
    void restBack() {
      if (widget.picker == null) {
        Navigator.of(context).maybePop();
      } else {
        ref.read(shellNavigatorProvider)?.call(DesktopTab.patients);
      }
    }

    final backLink = DetailsBackLink(label: restLabel, onBack: restBack);

    final Widget topRow;
    if (phone) {
      topRow = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              backLink,
              const SizedBox(width: CruSpace.s8),
              PatientAvatar(
                name: p.fullName,
                size: 40,
                allergic: allergies != null && !allergies.none,
                detailsPending: patientDetailsPending(p),
              ),
              const SizedBox(width: CruSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.fullName,
                      style: CruType.title2.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      PatientFormat.ageSexLong(p),
                      style: CruType.micro.tint(c.label2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (allergyPill != null) ...[
            const SizedBox(height: CruSpace.s8),
            Wrap(
              spacing: CruSpace.s8,
              runSpacing: CruSpace.s8,
              children: [allergyPill],
            ),
          ],
        ],
      );
    } else {
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
                physioTitle(context),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (allergyPill != null) ...[
                  const SizedBox(width: CruSpace.s20),
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: allergyPill,
                    ),
                  ),
                ],
                if (widget.picker != null) ...[
                  const SizedBox(width: CruSpace.s12),
                  SizedBox(width: 300, child: widget.picker),
                ],
              ],
            ),
          ),
        ],
      );
    }

    final switcher = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: CruSegmentedControl<PhysioTab>(
        semanticLabel: 'Physio',
        segments: [for (final t in PhysioTab.values) CruSegment(t, t.label)],
        selected: _tab,
        onChanged: _go,
      ),
    );

    final phoneBottomInset = phone ? MobileMetrics.bottom(context) : 0.0;
    Widget scroll(Widget child) => SingleChildScrollView(
      padding: EdgeInsets.only(bottom: phoneBottomInset),
      child: child,
    );

    final content = LayoutBuilder(
      builder: (context, box) {
        final wide = !phone && box.maxWidth >= CruBreakpoint.detailsTwoColumn;

        Widget workspace(PhysioTab t) => switch (t) {
          PhysioTab.assess => scroll(
            DetailsColumns(
              wide: wide,
              left: [MuscleChartCard(patient: p)],
              right: [
                ScreeningCard(patient: p),
                RomCard(patient: p),
                SpecialTestsCard(patient: p),
              ],
              narrow: [
                ScreeningCard(patient: p),
                MuscleChartCard(patient: p),
                RomCard(patient: p),
                SpecialTestsCard(patient: p),
              ],
            ),
          ),
          PhysioTab.progress => scroll(
            DetailsStack([
              GoalsCard(patient: p),
              ProgressCard(patient: p),
              OutcomeScalesCard(patient: p),
            ]),
          ),
          PhysioTab.treat => scroll(
            DetailsStack([
              HepCard(patient: p),
              ModalityCard(patient: p),
              SessionsCard(patient: p),
            ]),
          ),
          PhysioTab.records => scroll(
            DetailsStack([PhysioPhotosCard(patient: p)]),
          ),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topRow,
            const SizedBox(height: CruSpace.s12),
            if (!phone) ...[
              switcher,
              const SizedBox(height: CruSpace.s16),
            ],
            // Safety flags sit above the tabs' content on every tab, outside
            // the swiping area.
            ScreeningBanner(patient: p),
            Expanded(
              child: SwipePages<PhysioTab>(
                values: PhysioTab.values,
                value: _tab,
                onChanged: _go,
                keepAlive: true,
                builder: (context, t) =>
                    ExcludeFocus(excluding: t != _tab, child: workspace(t)),
              ),
            ),
          ],
        );
      },
    );

    Widget page = widget.embedded
        ? content
        : Scaffold(
            backgroundColor: c.canvas,
            body: Stack(
              children: [
                if (phone) const Positioned.fill(child: MobileBackdrop()),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: phone
                        ? CruSpace.mainPaddingPhone
                        : const EdgeInsets.fromLTRB(
                            CruSpace.s24,
                            CruSpace.s20,
                            CruSpace.s24,
                            CruSpace.s24,
                          ),
                    child: content,
                  ),
                ),
              ],
            ),
          );

    if (phone) {
      page = Stack(
        children: [
          page,
          Positioned(
            left: MobileMetrics.gutter,
            right: MobileMetrics.gutter,
            bottom: MobileMetrics.navBottom(context),
            child: _PhysioBottomBar(selected: _tab, onSelect: _go),
          ),
        ],
      );
    }

    return page;
  }
}

/// "Physio", in the page-title style every desktop page uses.
Widget physioTitle(BuildContext context, {bool phone = false}) => Semantics(
  header: true,
  child: Text(
    'Physio',
    style: (phone ? CruType.title2 : CruType.largeTitle).tint(
      context.cru.label,
    ),
  ),
);

/// The phone's floating tab bar for Physio (Assess, Progress, Treat, Records).
class _PhysioBottomBar extends StatelessWidget {
  const _PhysioBottomBar({required this.selected, required this.onSelect});

  final PhysioTab selected;
  final ValueChanged<PhysioTab> onSelect;

  static const _items = [
    MobileNavItem('Assess', PhysioIcons.physio),
    MobileNavItem('Progress', CruIcons.arrowUpRight),
    MobileNavItem('Treat', CruIcons.check),
    MobileNavItem('Records', CruIcons.fileText),
  ];

  @override
  Widget build(BuildContext context) => MobileNavBar.selection(
    showLabels: true,
    items: _items,
    selected: PhysioTab.values.indexOf(selected).clamp(0, _items.length - 1),
    onSelect: (i) => onSelect(PhysioTab.values[i]),
  );
}
