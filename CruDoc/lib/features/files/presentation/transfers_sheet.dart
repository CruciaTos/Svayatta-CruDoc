import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/file_offers_repository.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/data/wifi_offers.dart';
import 'package:doctor_management_app/features/files/lan/lan_server.dart';
import 'package:doctor_management_app/features/files/presentation/incoming_card.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Files colleagues sent to this person, any status, newest first.
final receivedOffersProvider = StreamProvider.autoDispose<List<FileOffer>>((
  ref,
) {
  final scope = ref.watch(offersScopeProvider);
  return FileOffersRepository.instance.watchReceivedOffers(
    clinicId: scope.clinicId,
    myUid: scope.uid,
  );
});

/// Files this person sent, any status, newest first.
final sentOffersProvider = StreamProvider.autoDispose<List<FileOffer>>((ref) {
  final scope = ref.watch(offersScopeProvider);
  return FileOffersRepository.instance.watchSentOffers(
    clinicId: scope.clinicId,
    myUid: scope.uid,
  );
});

/// Received files waiting for Accept or Decline: the count on the
/// Transfers button.
final waitingTransfersProvider = Provider<int>(
  (ref) => ref.watch(incomingOffersProvider).value?.length ?? 0,
);

/// Whether there is anyone in the clinic to send to or receive from: the
/// desktop colleague strip shows only then. Transfers always shows (its
/// history and errors are worth seeing even with no one to send to).
final hasColleaguesProvider = Provider<bool>((ref) {
  final me = FilesRepository.instance.uid;
  final clinic = FilesRepository.instance.doctorId;
  if (me.isEmpty || clinic.isEmpty) return false;
  // A member always has the owner as a colleague.
  if (clinic != me) return true;
  final members = ref.watch(clinicMembersProvider).value ?? const [];
  return members.any((m) => m.active && m.uid != me);
});

/// Received and sent files, with Accept / Decline / Cancel. A bottom sheet
/// on phones, a dialog on wider screens.
Future<void> showTransfersSheet(BuildContext context) {
  final c = context.cru;
  if (cruIsPhone(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CruRadius.card),
        ),
      ),
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: _TransfersBody(),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CruRadius.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: const _TransfersBody(),
      ),
    ),
  );
}

enum _Tab { received, sent }

class _TransfersBody extends ConsumerStatefulWidget {
  const _TransfersBody();

  @override
  ConsumerState<_TransfersBody> createState() => _TransfersBodyState();
}

class _TransfersBodyState extends ConsumerState<_TransfersBody> {
  _Tab _tab = _Tab.received;

  /// Offers whose Accept / Decline / Cancel is running.
  final Set<String> _busy = {};

  FileOffersRepository get _repo => FileOffersRepository.instance;

  Future<void> _run(
    String id,
    Future<void> Function() action,
    String failed,
  ) async {
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('$failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _accept(FileOffer o) => _run(o.id, () async {
    try {
      await _repo.acceptOffer(o);
      markOfferHandled(o.id);
    } on SenderNotOnWifiException {
      await WifiOffers.instance.wait(o);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'It will download when you’re on the same Wi-Fi as the sender',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }, "Couldn't accept");

  void _decline(FileOffer o) => _run(o.id, () async {
    await _repo.declineOffer(o);
    markOfferHandled(o.id);
  }, "Couldn't decline");

  void _cancel(FileOffer o) => _run(o.id, () async {
    await _repo.cancelOffer(o);
    LanServer.instance.unregisterOpenOffer(o.id);
  }, "Couldn't cancel");

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // Waiting ones include files that came only over Wi-Fi (no cloud copy
    // of the offer yet), so they come from the merged incoming list.
    final waiting = ref.watch(incomingOffersProvider).value ?? const [];
    final historyAsync = ref.watch(receivedOffersProvider);
    final sentAsync = ref.watch(sentOffersProvider);
    final history = historyAsync.value ?? const [];
    final sent = sentAsync.value ?? const [];
    final members = ref.watch(clinicMembersProvider).value ?? const [];
    final patients = ref.watch(patientsStreamProvider).value ?? const [];
    final canKeep = ref.watch(clinicCanProvider(ClinicPermission.clinicalEdit));

    final waitingIds = {for (final o in waiting) o.id};
    final received = [
      ...waiting,
      // A 'sent' one missing from [waiting] was just handled here; its
      // cloud update is on its way.
      for (final o in history)
        if (!waitingIds.contains(o.id) && o.status != FileOfferStatus.sent) o,
    ];

    String person(String uid) {
      for (final m in members) {
        if (m.uid == uid && m.name.trim().isNotEmpty) return m.name.trim();
      }
      return 'A colleague';
    }

    String patient(String id) {
      if (isUnassignedPatientId(id)) return 'No patient yet';
      for (final p in patients) {
        if (p.id == id) return p.fullName.trim();
      }
      return '';
    }

    final incoming = _tab == _Tab.received;
    final items = incoming ? received : sent;
    // A refused or failed list is not an empty one.
    final listError = (incoming ? historyAsync : sentAsync).error;
    final errorText = listError == null
        ? null
        : "Couldn't load ${incoming ? 'received' : 'sent'} files: $listError";

    return Padding(
      padding: const EdgeInsets.all(CruSpace.s20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Transfers',
                    style: CruType.headline.tint(c.label),
                  ),
                ),
              ),
              CruIconButton(
                icon: CruIcons.close,
                semanticLabel: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          CruSegmentedControl<_Tab>(
            semanticLabel: 'Received or sent',
            segments: [
              CruSegment(
                _Tab.received,
                waiting.isEmpty ? 'Received' : 'Received · ${waiting.length}',
              ),
              const CruSegment(_Tab.sent, 'Sent'),
            ],
            selected: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: CruSpace.s8),
          if (errorText != null && items.isNotEmpty)
            Text(errorText, style: CruType.caption.tint(c.label2)),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s32),
              child: Text(
                errorText ??
                    (incoming
                        ? 'Nothing received yet. Files colleagues send you show here.'
                        : 'Nothing sent yet.'),
                textAlign: TextAlign.center,
                style: CruType.text.tint(c.label2),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const CruSeparator(),
                itemBuilder: (_, i) {
                  final o = items[i];
                  return _OfferRow(
                    offer: o,
                    incoming: incoming,
                    who: person(incoming ? o.from : o.to),
                    patient: patient(o.patientId),
                    busy: _busy.contains(o.id),
                    canKeep: canKeep,
                    onAccept: () => _accept(o),
                    onDecline: () => _decline(o),
                    onCancel: () => _cancel(o),
                  );
                },
              ),
            ),
          if (!incoming) ...[
            const SizedBox(height: CruSpace.s12),
            Text(
              "To send a file, open its ⋯ menu and choose Send to colleague.",
              textAlign: TextAlign.center,
              style: CruType.caption.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.offer,
    required this.incoming,
    required this.who,
    required this.patient,
    required this.busy,
    required this.canKeep,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  final FileOffer offer;
  final bool incoming;
  final String who;
  final String patient;
  final bool busy;

  /// May save patient files (write clinical records): Accept needs it.
  final bool canKeep;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'Yesterday';
    return '${t.day} ${_months[t.month - 1]}';
  }

  static CruIconData _icon(String contentType) =>
      switch (PatientFileTypes.kindOf(contentType)) {
        FileKind.image => FileIcons.image,
        FileKind.scan => FileIcons.scan,
        FileKind.video => FileIcons.video,
        FileKind.audio => FileIcons.audio,
        _ => CruIcons.fileText,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final waiting = offer.status == FileOfferStatus.sent;
    final detail = [
      if (waiting && !incoming) 'Waiting',
      if (offer.subject.isNotEmpty) offer.subject,
      incoming ? 'From $who' : 'To $who',
      if (patient.isNotEmpty) patient,
      _ago(offer.createdAt),
      offer.via == FileOfferVia.lan ? 'Wi-Fi' : 'Cloud',
    ].join(' · ');

    final Widget trailing;
    if (busy) {
      trailing = SizedBox.square(
        dimension: CruSize.capsule,
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s8),
          child: CircularProgressIndicator(strokeWidth: 2, color: c.label2),
        ),
      );
    } else if (waiting && incoming) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CruCapsuleButton(label: 'Decline', onPressed: onDecline),
          const SizedBox(width: CruSpace.s8),
          CruCapsuleButton(
            label: 'Accept',
            kind: CruCapsuleKind.tinted,
            onPressed: canKeep ? onAccept : null,
          ),
        ],
      );
    } else if (waiting) {
      trailing = CruCapsuleButton(label: 'Cancel', onPressed: onCancel);
    } else {
      trailing = _StatusPill(switch (offer.status) {
        FileOfferStatus.accepted => incoming ? 'Saved' : 'Accepted',
        FileOfferStatus.declined => 'Declined',
        _ => 'Cancelled',
      }, done: offer.status == FileOfferStatus.accepted);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
      child: Row(
        children: [
          CruIconTile(
            icon: _icon(offer.contentType),
            tone: CruTileTone.neutral,
          ),
          const SizedBox(width: CruSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.name.isEmpty ? 'File' : offer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.row.tint(c.label),
                ),
                const SizedBox(height: CruSpace.s2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.caption.tint(c.label2),
                ),
                if (offer.note.isNotEmpty) ...[
                  const SizedBox(height: CruSpace.s2),
                  Text(
                    offer.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.caption.tint(c.label3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s12),
          trailing,
        ],
      ),
    );
  }
}

/// Green when done; neutral for declined or cancelled.
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text, {this.done = false});

  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: done ? c.greenTint : c.inset,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s4,
        ),
        child: Text(
          text,
          style: CruType.chip.tint(done ? c.greenText : c.label2),
        ),
      ),
    );
  }
}
