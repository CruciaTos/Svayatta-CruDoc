import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "‹ Patients" on the left; Edit, "…" and New visit on the right.
class DetailsTopBar extends StatelessWidget {
  const DetailsTopBar({
    super.key,
    required this.patientName,
    required this.onBack,
    required this.onEdit,
    required this.onNewVisit,
    required this.onDelete,
    this.onDentalChart,
    this.onCaseSheet,
  });

  final String patientName;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onNewVisit;
  final VoidCallback onDelete;

  /// Dentists only.
  final VoidCallback? onDentalChart;

  /// Homeopaths only.
  final VoidCallback? onCaseSheet;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DetailsBackLink(onBack: onBack),
        const Spacer(),
        CruButton(
          label: 'Edit',
          kind: CruButtonKind.secondary,
          icon: CruIcons.pen,
          onPressed: onEdit,
        ),
        const SizedBox(width: CruSpace.s10),
        _MoreMenu(
          patientName: patientName,
          onDentalChart: onDentalChart,
          onCaseSheet: onCaseSheet,
          onDelete: onDelete,
        ),
        const SizedBox(width: CruSpace.s10),
        CruButton(label: 'New visit', icon: CruIcons.plus, onPressed: onNewVisit),
      ],
    );
  }
}

/// "‹ Patients" (15/500 accentText, 40 px tall).
class DetailsBackLink extends StatelessWidget {
  const DetailsBackLink({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: CruSize.control,
      child: Align(
        alignment: Alignment.centerLeft,
        child: CruLink(
          label: 'Patients',
          onPressed: onBack,
          style: CruType.input.w500,
          leading: const CruIcon(CruIcons.chevronLeft, size: 20, strokeWidth: 2),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.patientName,
    required this.onDelete,
    this.onDentalChart,
    this.onCaseSheet,
  });

  final String patientName;
  final VoidCallback onDelete;
  final VoidCallback? onDentalChart;
  final VoidCallback? onCaseSheet;

  @override
  Widget build(BuildContext context) {
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
    return MenuAnchor(
      alignmentOffset: const Offset(0, CruSpace.s6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: WidgetStatePropertyAll(c.surface.withValues(alpha: 0)),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.12)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.all(CruSpace.s6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        if (onDentalChart != null)
          MenuItemButton(
            style: itemStyle,
            onPressed: onDentalChart,
            child: const Text('Dental chart and procedures'),
          ),
        if (onCaseSheet != null)
          MenuItemButton(
            style: itemStyle,
            onPressed: onCaseSheet,
            child: const Text('Case sheet'),
          ),
        MenuItemButton(
          style: itemStyle,
          onPressed: onDelete,
          child: const Text('Delete patient'),
        ),
      ],
      builder: (context, controller, _) => CruSquareButton(
        icon: CruIcons.more,
        secondary: true,
        semanticLabel: 'More actions for $patientName',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
