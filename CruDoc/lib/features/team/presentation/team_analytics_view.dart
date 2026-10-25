import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/dashboard/domain/dashboard_format.dart';
import 'package:doctor_management_app/features/mobile/activity/activity_feed.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/revenue/repo/invoice_repo.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/domain/team_stats.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The periods the admin can look back over, in days.
enum _Period {
  week(7, '7 days'),
  month(30, '30 days'),
  quarter(90, '90 days');

  const _Period(this.days, this.label);
  final int days;
  final String label;
}

final teamInvoicesProvider = StreamProvider.autoDispose<List<InvoiceModel>>(
  (ref) => InvoiceRepository().watchInvoices(),
);

/// Records opened and files downloaded in the clinic since a day, newest
/// first. Capped: the counts are a picture of the team, not an audit.
final teamLogsProvider = StreamProvider.autoDispose
    .family<List<TeamLogEntry>, DateTime>((ref, from) {
      final clinicId = ref.watch(clinicAccessProvider).value?.clinicId;
      if (clinicId == null) return Stream.value(const []);
      return FirebaseFirestore.instance
          .collection('access_logs')
          .where('doctorId', isEqualTo: clinicId)
          .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .orderBy('at', descending: true)
          .limit(2000)
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                if (d.data()['at'] case final Timestamp at)
                  TeamLogEntry(
                    actorUid: '${d.data()['actorUid'] ?? ''}',
                    action: '${d.data()['action'] ?? ''}',
                    at: at.toDate(),
                  ),
            ],
          );
    });

/// Settings → Team → Analytics: what each person in the clinic did over a
/// period. For the clinic's owner and admins only (TeamSection decides).
class TeamAnalyticsView extends ConsumerStatefulWidget {
  const TeamAnalyticsView({super.key});

  @override
  ConsumerState<TeamAnalyticsView> createState() => _TeamAnalyticsViewState();
}

class _TeamAnalyticsViewState extends ConsumerState<TeamAnalyticsView> {
  _Period _period = _Period.month;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(Duration(days: _period.days - 1));
    final to = today.add(const Duration(days: 1));

    final members = (ref.watch(clinicMembersProvider).value ?? const [])
        .where((m) => m.active)
        .toList();
    final visits = ref.watch(allVisitsProvider);
    final queue = ref.watch(allQueueProvider);
    final revenue = ref.watch(recentRevenueEntriesProvider);
    final invoices = ref.watch(teamInvoicesProvider);
    final logs = ref.watch(teamLogsProvider(from));

    final loading = [
      visits,
      queue,
      revenue,
      invoices,
      logs,
    ].any((a) => a.isLoading && !a.hasValue);
    final stats = TeamStats.compute(
      from: from,
      to: to,
      visits: visits.value ?? const [],
      queue: queue.value ?? const [],
      revenue: revenue.value ?? const [],
      invoices: invoices.value ?? const [],
      logs: logs.value ?? const [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Last ${_period.label}',
                style: CruType.headline.tint(c.label),
              ),
            ),
            CruSegmentedControl<_Period>(
              segments: [
                for (final p in _Period.values) CruSegment(p, p.label),
              ],
              selected: _period,
              onChanged: (p) => setState(() => _period = p),
            ),
          ],
        ),
        const SizedBox(height: CruSpace.cardGap),
        CruCard(
          child: Wrap(
            spacing: CruSpace.s24,
            runSpacing: CruSpace.s16,
            children: [
              _Figure('Appointments booked', '${stats.clinic.booked}'),
              _Figure('Visits completed', '${stats.clinic.completed}'),
              _Figure('Queue check-ins', '${stats.clinic.checkedIn}'),
              _Figure('Collected', DashFormat.rupees(stats.clinic.collected)),
              _Figure('Records opened', '${stats.clinic.recordsOpened}'),
            ],
          ),
        ),
        if (logs.hasError || invoices.hasError) ...[
          const SizedBox(height: CruSpace.s8),
          Text(
            logs.hasError
                ? "Couldn't load records opened and files downloaded."
                : "Couldn't load invoices.",
            style: CruType.caption.tint(c.label2),
          ),
        ],
        const SizedBox(height: CruSpace.cardGap),
        if (loading && members.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(CruSpace.s24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final m in members) ...[
            _PersonCard(member: m, stats: stats.of(m.uid), now: now),
            const SizedBox(height: CruSpace.cardGap),
          ],
        if (stats.unattributed > 0)
          Text(
            stats.unattributed == 1
                ? '1 record in this period was made before CruDoc noted who '
                      'made it. It counts for the clinic, not for one person.'
                : '${stats.unattributed} records in this period were made '
                      'before CruDoc noted who made them. They count for the '
                      'clinic, not for one person.',
            style: CruType.caption.tint(c.label3),
          ),
      ],
    );
  }
}

/// One person: who they are, when they last did something, and their
/// numbers for the period in three groups.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.member,
    required this.stats,
    required this.now,
  });

  final ClinicMember member;
  final MemberStats stats;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final last = stats.lastActivity;
    final role = member.isOwner ? 'Owner' : member.roleName;
    return CruCard(
      padding: EdgeInsets.only(
        bottom: stats.isEmpty ? CruSpace.s4 : CruSpace.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamRow(
            monogram: member.name,
            title: member.name.isEmpty ? 'Unnamed' : member.name,
            detail: [
              if (role.isNotEmpty) role,
              last == null
                  ? 'No activity in this period'
                  : 'Last activity ${activityAgo(last, now).toLowerCase()}',
            ].join(' · '),
          ),
          if (!stats.isEmpty) ...[
            const CruSeparator(indent: CruSpace.s16),
            const SizedBox(height: CruSpace.s12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
              child: Wrap(
                spacing: CruSpace.s24,
                runSpacing: CruSpace.s16,
                children: [
                  _Group('Patients', [
                    ('Booked', '${stats.booked}'),
                    ('Attended', '${stats.attended}'),
                    ('Completed', '${stats.completed}'),
                    ('Checked in', '${stats.checkedIn}'),
                  ]),
                  _Group('Money', [
                    ('Collected', DashFormat.rupees(stats.collected)),
                    ('Invoices', '${stats.invoices}'),
                  ]),
                  _Group('Activity', [
                    ('Records opened', '${stats.recordsOpened}'),
                    ('Files', '${stats.filesDownloaded}'),
                  ]),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled group of small figures ("Patients: Booked 12 · Attended 9").
class _Group extends StatelessWidget {
  const _Group(this.title, this.items);

  final String title;
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: CruType.groupLabel.tint(c.label3)),
        const SizedBox(height: CruSpace.s8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: CruSpace.s16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[i].$2,
                    style: CruType.headline.tabular.tint(c.label),
                  ),
                  Text(items[i].$1, style: CruType.caption.tint(c.label2)),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A clinic-wide figure: big number over its label.
class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: CruType.metric.tabular.tint(c.label)),
        const SizedBox(height: CruSpace.s2),
        Text(label, style: CruType.subhead.tint(c.label2)),
      ],
    );
  }
}
