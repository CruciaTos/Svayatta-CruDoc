import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/dashboard/presentation/widgets/dashboard_search_field.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Date line + greeting, then search, Add patient and New visit (these
/// replace the old Quick Actions card and the floating chat button).
class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({super.key, this.searchFocusNode});

  final FocusNode? searchFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final now = ref.watch(dashboardNowProvider);
    final name = ref.watch(doctorIdentityProvider).greetingName;
    final greeting = DashFormat.greeting(now);

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.isEvening) ...[
              CruIcon(CruIcons.moon, size: 14, strokeWidth: 2, color: c.label2),
              const SizedBox(width: CruSpace.s6),
            ],
            Flexible(
              child: Text(
                c.isEvening
                    ? '${DashFormat.dateLine(now)} · Evening session'
                    : DashFormat.dateLine(now),
                style: CruType.dateLine.tint(c.label2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.s4),
        Semantics(
          header: true,
          child: Text(
            name == null ? greeting : '$greeting, $name',
            style: CruType.largeTitle.tint(c.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    Widget actions({required bool stretchSearch}) => Row(
          mainAxisSize: stretchSearch ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (stretchSearch)
              Expanded(child: DashboardSearchField(focusNode: searchFocusNode))
            else
              DashboardSearchField(
                focusNode: searchFocusNode,
                width: CruSize.searchWidth,
              ),
            const SizedBox(width: CruSpace.s10),
            CruButton(
              label: 'Add patient',
              kind: CruButtonKind.secondary,
              icon: CruIcons.userPlus,
              onPressed: () => DashboardActions.addPatient(context),
            ),
            const SizedBox(width: CruSpace.s10),
            CruButton(
              label: 'New visit',
              icon: CruIcons.plus,
              onPressed: () => DashboardActions.newVisit(context),
            ),
          ],
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side needs room for the greeting plus ~570 px of actions.
        if (constraints.maxWidth >= 1040) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: title),
              const SizedBox(width: CruSpace.s24),
              actions(stretchSearch: false),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: CruSpace.s16),
            actions(stretchSearch: true),
          ],
        );
      },
    );
  }
}
