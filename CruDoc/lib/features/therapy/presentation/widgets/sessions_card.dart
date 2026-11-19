import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/therapy/domain/physio_extras_models.dart';
import 'package:doctor_management_app/features/therapy/presentation/sessions_screen.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patient Details card for physiotherapists: sessions left in the latest
/// package, one tap to use a session.
class SessionsCard extends ConsumerWidget {
  const SessionsCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patient.id,
        kind: RecKind.physioPackage,
      )),
    );
    final latest = sessionPackages(
      recs.value ?? const <DentalRecord>[],
    ).firstOrNull;

    final String subtitle;
    if (latest == null) {
      subtitle = 'Track a package of sessions';
    } else if (latest.completed) {
      subtitle = latest.name;
    } else {
      subtitle = '${latest.left} of ${latest.total} left';
    }

    return CruCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(CruRadius.control),
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionsScreen(patient: patient),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.inset,
                    borderRadius: BorderRadius.circular(CruRadius.control),
                  ),
                  child: Icon(
                    Icons.event_repeat_rounded,
                    size: 18,
                    color: c.label2,
                  ),
                ),
                const SizedBox(width: CruSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sessions',
                        style: CruType.headline.w600.tint(c.label),
                      ),
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        subtitle,
                        style: CruType.caption.tabular.tint(c.label2),
                      ),
                    ],
                  ),
                ),
                if (latest != null && !latest.completed) ...[
                  CruCapsuleButton(
                    label: 'Use session',
                    onPressed: () => useSession(context, ref, latest),
                  ),
                  const SizedBox(width: CruSpace.s8),
                ],
                CruCapsuleButton(
                  label: latest == null || latest.completed
                      ? 'New package'
                      : 'New',
                  icon: latest == null || latest.completed
                      ? CruIcons.plus
                      : null,
                  onPressed: () => showNewPackageSheet(context, ref, patient),
                ),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: CruSpace.s12),
              _Bar(used: latest.used.length, total: latest.total),
              const SizedBox(height: CruSpace.s8),
              Wrap(
                spacing: CruSpace.s8,
                runSpacing: CruSpace.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    latest.name,
                    style: CruType.caption.w600.tint(c.label),
                  ),
                  if (latest.validUntil != null)
                    Text(
                      'Valid until ${DentalFormat.date(latest.validUntil!)}',
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                  if (latest.completed)
                    CruPill(
                      text: 'Completed',
                      background: c.greenTint,
                      foreground: c.greenText,
                    )
                  else if (latest.expired)
                    CruPill(
                      text: 'Expired',
                      background: c.amberTint,
                      foreground: c.amberText,
                    )
                  else if (latest.low)
                    CruPill(
                      text: '${latest.left} left',
                      background: c.amberTint,
                      foreground: c.amberText,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dots for small packages, a thin bar for large ones.
class _Bar extends StatelessWidget {
  const _Bar({required this.used, required this.total});

  final int used;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    if (total > 20) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(CruRadius.full),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : (used / total).clamp(0, 1),
          minHeight: CruSize.smallDot,
          backgroundColor: c.inset,
          color: c.accent,
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: CruSpace.s4),
          Expanded(
            child: Container(
              height: CruSize.smallDot,
              decoration: BoxDecoration(
                color: i < used ? c.accent : c.inset,
                borderRadius: BorderRadius.circular(CruRadius.full),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
