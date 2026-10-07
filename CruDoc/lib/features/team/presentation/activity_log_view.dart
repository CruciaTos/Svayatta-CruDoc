import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Rows fetched per "Show more".
const int _kPage = 50;

/// Who did what in the clinic: patient records opened, files downloaded,
/// and every team change. Newest first.
class ActivityLogView extends ConsumerStatefulWidget {
  const ActivityLogView({super.key});

  @override
  ConsumerState<ActivityLogView> createState() => _ActivityLogViewState();
}

class _ActivityLogViewState extends ConsumerState<ActivityLogView> {
  int _limit = _kPage;

  /// Only this person's actions; '' is everyone.
  String _who = '';

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final clinicId = ref.watch(clinicAccessProvider).value?.clinicId;
    final members = ref.watch(clinicMembersProvider).value ?? const [];
    final roles = ref.watch(clinicRolesProvider).value ?? const <ClinicRole>[];
    if (clinicId == null) return const SizedBox.shrink();
    final names = {for (final m in members) m.uid: m.name};
    final roleNames = {for (final r in roles) r.id: r.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CruDropdownField<String>(
          label: 'Person',
          value: _who,
          items: ['', for (final m in members) m.uid],
          itemLabel: (uid) => uid.isEmpty ? 'Everyone' : (names[uid] ?? uid),
          onChanged: (uid) => setState(() {
            _who = uid;
            _limit = _kPage;
          }),
        ),
        const SizedBox(height: CruSpace.cardGap),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('access_logs')
              .where('doctorId', isEqualTo: clinicId)
              .orderBy('at', descending: true)
              .limit(_limit)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                "Couldn't load the activity log.",
                style: CruType.text.tint(c.label2),
              );
            }
            final docs = snapshot.data?.docs ?? const [];
            final rows = [
              for (final d in docs)
                if (_who.isEmpty || d.data()['actorUid'] == _who) d.data(),
            ];
            if (snapshot.connectionState == ConnectionState.waiting &&
                docs.isEmpty) {
              return const SizedBox.shrink();
            }
            return TeamGroupCard(
              title: 'Activity',
              rows: [
                if (rows.isEmpty)
                  const TeamRow(title: 'Nothing yet')
                else
                  for (final row in rows)
                    TeamRow(
                      title: _sentence(row, names, roleNames),
                      detail: [
                        names[row['actorUid']] ?? 'Removed member',
                        if (row['at'] case final Timestamp at)
                          DateFormat('d MMM, h:mm a').format(at.toDate()),
                      ].join(' · '),
                    ),
                if (docs.length >= _limit)
                  TeamRow(
                    title: 'Show more',
                    onTap: () => setState(() => _limit += _kPage),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _sentence(
    Map<String, dynamic> row,
    Map<String, String> names,
    Map<String, String> roleNames,
  ) {
    final target = '${row['target'] ?? ''}';
    final person = names[target] ?? 'someone';
    return switch (row['action']) {
      'patient.view' => 'Opened a patient record',
      'file.download' => 'Downloaded a file',
      'image.view' => 'Viewed a scan',
      'team.create' => 'Set up the clinic team',
      'team.invite' => 'Sent an invite',
      'invite.cancel' => 'Cancelled an invite',
      'team.join' => 'Joined the clinic',
      'team.update' => 'Changed $person\'s role or features',
      'team.remove' => 'Removed $person',
      'role.save' when roleNames[target] != null =>
        'Saved the ${roleNames[target]} role',
      'role.save' => 'Saved a role',
      'role.delete' => 'Deleted a role',
      final other => '$other',
    };
  }
}
