import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/files/data/colleague_send.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/lan/device_registry_service.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Shows the "Send to colleague" sheet.
Future<void> showSendToColleagueSheet(
  BuildContext context,
  WidgetRef ref,
  List<PatientFile> files,
) async {
  if (files.isEmpty) return;

  final clinicId = FilesRepository.instance.doctorId;
  final myUid = FilesRepository.instance.uid;
  if (clinicId.isEmpty || myUid.isEmpty) return;

  final members = ref.read(clinicMembersProvider).value ?? const [];
  final colleagues = members.where((m) => m.uid != myUid && m.active).toList();

  if (colleagues.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('No colleagues in your clinic to send to.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  // Load patient to check assignments if needed
  final patientId = files.first.patientId;
  final allPatients = ref.read(patientsStreamProvider).value ?? const [];
  final patient = allPatients.where((p) => p.id == patientId).firstOrNull;

  final access = ClinicSession.instance.access;
  final isScopedClinic = access?.clinicalAccessScope == 'assigned';

  await showModalBottomSheet<void>(
    context: Navigator.of(context, rootNavigator: true).context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SendSheet(
      clinicId: clinicId,
      files: files,
      colleagues: colleagues,
      patient: patient,
      isScopedClinic: isScopedClinic,
    ),
  );
}

class _SendSheet extends StatefulWidget {
  const _SendSheet({
    required this.clinicId,
    required this.files,
    required this.colleagues,
    required this.patient,
    required this.isScopedClinic,
  });

  final String clinicId;
  final List<PatientFile> files;
  final List<ClinicMember> colleagues;
  final Patient? patient;
  final bool isScopedClinic;

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  bool _sending = false;
  String? _sendingToName;

  String? _ineligibleReason(ClinicMember m) {
    return colleagueBlockReason(m, patient: widget.patient);
  }

  Future<void> _sendTo(ClinicMember colleague) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _sendingToName = colleague.name;
    });

    try {
      final offers = await sendFilesToColleague(
        clinicId: widget.clinicId,
        colleague: colleague,
        files: widget.files,
      );
      final via = offers.isNotEmpty ? offers.first.via : FileOfferVia.cloud;

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              via == FileOfferVia.lan
                  ? 'Sent direct on clinic Wi-Fi ⚡'
                  : 'Sent via cloud ☁',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final title = widget.files.length == 1
        ? 'Send “${widget.files.first.name}”'
        : 'Send ${widget.files.length} files';

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        CruSpace.s20,
        CruSpace.s16,
        CruSpace.s20,
        MediaQuery.paddingOf(context).bottom + CruSpace.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: CruSpace.s16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CruType.headline),
                    const SizedBox(height: 2),
                    Text(
                      'Choose a colleague in your clinic',
                      style: CruType.subhead.tint(c.label2),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s16),
          if (_sending) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s24),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: CruSpace.s16),
                  Text(
                    'Sending to $_sendingToName…',
                    style: CruType.body.tint(c.label),
                  ),
                ],
              ),
            ),
          ] else ...[
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.colleagues.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final colleague = widget.colleagues[i];
                  final reason = _ineligibleReason(colleague);
                  final eligible = reason == null;

                  final cachedPeer = DeviceRegistryService
                      .instance
                      .cachedDevices
                      .where((d) => d.uid == colleague.uid && d.hasLanEndpoint)
                      .firstOrNull;
                  final transportLabel = cachedPeer != null
                      ? '⚡ Nearby on Wi-Fi'
                      : '☁ Will go through the cloud';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: CruSpace.s8,
                      vertical: CruSpace.s4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: eligible ? c.accentWash : c.hoverFill,
                      foregroundColor: eligible ? c.accentText : c.label3,
                      child: Text(
                        colleague.name.isNotEmpty
                            ? colleague.name.characters.first.toUpperCase()
                            : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      colleague.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: eligible ? c.label : c.label3,
                      ),
                    ),
                    subtitle: Text(
                      reason ?? transportLabel,
                      style: CruType.caption.tint(
                        eligible
                            ? (cachedPeer != null ? Colors.green : c.label2)
                            : c.label3,
                      ),
                    ),
                    enabled: eligible,
                    onTap: eligible ? () => _sendTo(colleague) : null,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
