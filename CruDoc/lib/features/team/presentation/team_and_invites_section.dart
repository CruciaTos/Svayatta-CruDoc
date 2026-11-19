import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/team/presentation/clinic_invites_section.dart';
import 'package:doctor_management_app/features/team/presentation/team_section.dart';

/// Settings → Team & invites: waiting invites (if any), the clinic's team
/// (only with the `team` permission), then the person's own ID and number.
class TeamAndInvitesSection extends ConsumerWidget {
  const TeamAndInvitesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(clinicAccessProvider).value;
    final showTeam = access != null && access.can(ClinicPermission.team);
    return ClinicInvitesSection(between: showTeam ? const TeamSection() : null);
  }
}
