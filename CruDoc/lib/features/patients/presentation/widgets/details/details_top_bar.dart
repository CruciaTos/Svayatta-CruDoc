import 'package:flutter/material.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';

/// "‹ Patients" (15/500 accentText, 40 px tall); "‹ Schedule" etc. when
/// details were opened from another screen.
class DetailsBackLink extends ConsumerWidget {
  const DetailsBackLink({super.key, required this.onBack, this.label});
  final VoidCallback onBack;

  /// In place of where details were opened from ("Overview" inside a
  /// sub-screen).
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final back = ref.watch(patientDetailsReturnTabProvider);
    final label = this.label;
    if (label != null) {
      return SizedBox(
        height: CruSize.control,
        child: Align(
          alignment: Alignment.centerLeft,
          child: CruLink(
            label: label,
            onPressed: onBack,
            style: CruType.input.w500,
            leading: const CruIcon(
              CruIcons.chevronLeft,
              size: 20,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: CruSize.control,
      child: Align(
        alignment: Alignment.centerLeft,
        child: CruLink(
          label: back == null ? 'Patients' : DesktopTab.label(back),
          onPressed: onBack,
          style: CruType.input.w500,
          leading: const CruIcon(
            CruIcons.chevronLeft,
            size: 20,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

/// One item in the ••• menu.
typedef DetailsMenuItem = ({String label, VoidCallback onPressed});

/// The ••• menu on Patient details: "Create" (bill, prescription, report,
/// certificate) and "Patient" (edit, delete). Only what the person's role
/// allows is passed in; with nothing to show the button is left out.
class DetailsMoreMenu extends StatelessWidget {
  const DetailsMoreMenu({
    super.key,
    required this.patientName,
    required this.create,
    required this.manage,
  });

  final String patientName;
  final List<DetailsMenuItem> create;
  final List<DetailsMenuItem> manage;

  @override
  Widget build(BuildContext context) {
    if (create.isEmpty && manage.isEmpty) return const SizedBox.shrink();
    final c = context.cru;
    final itemStyle = ButtonStyle(
      textStyle: WidgetStatePropertyAll(CruType.text.w500),
      foregroundColor: WidgetStatePropertyAll(c.label),
      overlayColor: WidgetStatePropertyAll(c.hoverFill),
      minimumSize: const WidgetStatePropertyAll(Size(220, CruSize.control)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: CruSpace.s14),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CruRadius.keycap),
        ),
      ),
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s14,
        CruSpace.s8,
        CruSpace.s14,
        CruSpace.s4,
      ),
      child: Text(text, style: CruType.groupLabel.tint(c.label3)),
    );
    List<Widget> items(List<DetailsMenuItem> list) => [
      for (final i in list)
        MenuItemButton(
          style: itemStyle,
          onPressed: i.onPressed,
          child: Text(i.label),
        ),
    ];
    return MenuAnchor(
      alignmentOffset: const Offset(0, CruSpace.s6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: WidgetStatePropertyAll(
          c.surface.withValues(alpha: 0),
        ),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.12)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        if (create.isNotEmpty) ...[label('Create'), ...items(create)],
        if (create.isNotEmpty && manage.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: CruSpace.s4),
            child: CruSeparator(),
          ),
        if (manage.isNotEmpty) ...[label('Patient'), ...items(manage)],
      ],
      builder: (context, controller, _) => CruSquareButton(
        icon: CruIcons.more,
        secondary: true,
        semanticLabel: 'More actions for $patientName',
        tooltip: 'More',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
