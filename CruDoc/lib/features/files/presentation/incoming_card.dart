import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/file_offers_repository.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/lan/lan_server.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Provider for stream of incoming file offers for the signed-in user,
/// merging both cloud offers and real-time direct LAN offers (Tasks O3, N2, M4).
final incomingOffersProvider = StreamProvider<List<FileOffer>>((ref) {
  final clinicId = FilesRepository.instance.doctorId;
  final myUid = FilesRepository.instance.uid;
  if (clinicId.isEmpty || myUid.isEmpty) {
    return Stream.value(const []);
  }

  final controller = StreamController<List<FileOffer>>();
  final offersMap = <String, FileOffer>{};
  // Ids a cloud answer has listed: when a later answer leaves one out, it
  // was accepted, declined or cancelled (Wi-Fi copies of it included).
  final cloudSeen = <String>{};

  void emit() {
    final list = offersMap.values
        .where(
          (o) =>
              o.status == FileOfferStatus.sent &&
              !_handledOfferIds.contains(o.id),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!controller.isClosed) controller.add(list);
  }

  final handledSub = _handledChanges.stream.listen((_) => emit());
  final firestoreSub = FileOffersRepository.instance
      .watchIncomingOffers(clinicId: clinicId, myUid: myUid)
      .listen(
        (cloudOffers) {
          final now = {for (final o in cloudOffers) o.id};
          offersMap.removeWhere(
            (id, _) => cloudSeen.contains(id) && !now.contains(id),
          );
          cloudSeen
            ..clear()
            ..addAll(now);
          for (final o in cloudOffers) {
            offersMap[o.id] = o;
          }
          emit();
        },
        // Refused (rules not deployed, or no clinical access) or offline:
        // Wi-Fi offers still arrive. Unhandled, this error paused the app.
        onError: (Object e) => debugPrint('[IncomingOffers] cloud offers: $e'),
      );

  final lanSub = LanServer.instance.incomingLanOffers.listen((lanOffer) {
    if (lanOffer.to == myUid) {
      offersMap[lanOffer.id] = lanOffer;
      emit();
    }
  });

  ref.onDispose(() {
    handledSub.cancel();
    firestoreSub.cancel();
    lanSub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Offers accepted or declined on this device. An offer that came only
/// over Wi-Fi (no internet) never gets a cloud update, so this is what
/// takes it out of the waiting list.
final Set<String> _handledOfferIds = {};
final StreamController<void> _handledChanges = StreamController.broadcast();

void markOfferHandled(String offerId) {
  _handledOfferIds.add(offerId);
  _handledChanges.add(null);
}

/// Displays a prominent card at the top of Files when incoming offers are waiting.
class IncomingOffersCard extends ConsumerStatefulWidget {
  const IncomingOffersCard({super.key});

  @override
  ConsumerState<IncomingOffersCard> createState() => _IncomingOffersCardState();
}

class _IncomingOffersCardState extends ConsumerState<IncomingOffersCard> {
  final Set<String> _processingBatches = {};

  Future<void> _acceptBatch(List<FileOffer> batch, {bool alwaysAccept = false}) async {
    final batchId = batch.first.batchId;
    if (_processingBatches.contains(batchId)) return;
    setState(() => _processingBatches.add(batchId));

    try {
      if (alwaysAccept) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('crudoc.files.autoAccept.${batch.first.from}', true);
      }

      for (final offer in batch) {
        await FileOffersRepository.instance.acceptOffer(offer);
        markOfferHandled(offer.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              batch.length == 1
                  ? 'Accepted “${batch.first.name}”'
                  : 'Accepted ${batch.length} files',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingBatches.remove(batchId));
      }
    }
  }

  Future<void> _declineBatch(List<FileOffer> batch) async {
    final batchId = batch.first.batchId;
    if (_processingBatches.contains(batchId)) return;
    setState(() => _processingBatches.add(batchId));

    try {
      for (final offer in batch) {
        await FileOffersRepository.instance.declineOffer(offer);
        markOfferHandled(offer.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingBatches.remove(batchId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(incomingOffersProvider);
    final offers = async.value ?? const [];
    if (offers.isEmpty) return const SizedBox.shrink();

    final members = ref.watch(clinicMembersProvider).value ?? const [];
    final patients = ref.watch(patientsStreamProvider).value ?? const [];

    // Group offers by batchId
    final batches = <String, List<FileOffer>>{};
    for (final o in offers) {
      batches.putIfAbsent(o.batchId, () => []).add(o);
    }

    return Column(
      children: [
        for (final entry in batches.entries)
          _buildBatchCard(
            context,
            entry.value,
            members,
            patients,
            _processingBatches.contains(entry.key),
          ),
      ],
    );
  }

  Widget _buildBatchCard(
    BuildContext context,
    List<FileOffer> batch,
    List<dynamic> members,
    List<dynamic> patients,
    bool isProcessing,
  ) {
    final c = context.cru;
    final first = batch.first;
    final sender = members.where((m) => m.uid == first.from).firstOrNull;
    final senderName = sender?.name.isNotEmpty == true
        ? (sender!.name.startsWith('Dr') ? sender.name : 'Dr. ${sender.name}')
        : 'A colleague';

    final patient = patients.where((p) => p.id == first.patientId).firstOrNull;
    final patientName = patient?.fullName?.trim().isNotEmpty == true
        ? patient!.fullName.trim()
        : 'Patient';

    final title = batch.length == 1
        ? '$senderName shared “${first.name}” for $patientName'
        : '$senderName shared ${batch.length} files for $patientName';

    return Container(
      margin: const EdgeInsets.only(bottom: CruSpace.s12),
      padding: const EdgeInsets.all(CruSpace.s16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.accent.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.accentWash,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.move_to_inbox, color: c.accentText, size: 20),
              ),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: CruType.body.w600),
                    const SizedBox(height: 2),
                    Text(
                      'Ready to add to your records for $patientName',
                      style: CruType.caption.tint(c.label2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          if (isProcessing) ...[
            const Center(child: CircularProgressIndicator()),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _declineBatch(batch),
                  child: Text(
                    'Decline',
                    style: TextStyle(color: c.label2),
                  ),
                ),
                const SizedBox(width: CruSpace.s8),
                ElevatedButton(
                  onPressed: () => _acceptBatch(batch),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
