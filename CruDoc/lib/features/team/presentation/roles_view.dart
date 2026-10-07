import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/role_editor_sheet.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The clinic's roles with how many people hold each. Custom roles are the
/// clinic's own staff categories.
class RolesView extends ConsumerWidget {
  const RolesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(clinicRolesProvider).value ?? const <ClinicRole>[];
    final members = ref.watch(clinicMembersProvider).value ?? const [];
    String countFor(ClinicRole r) {
      final n = members.where((m) => m.active && m.roleId == r.id).length;
      final people = n == 1 ? '1 person' : '$n people';
      return r.id == 'admin' ? '$people · Can do everything' : people;
    }

    return TeamGroupCard(
      title: 'Roles',
      trailing: CruCapsuleButton(
        label: 'New role',
        onPressed: () => showRoleEditor(context),
      ),
      rows: [
        for (final r in roles)
          TeamRow(
            title: r.name,
            detail: countFor(r),
            onTap: () => showRoleEditor(context, role: r),
          ),
      ],
    );
  }
}
