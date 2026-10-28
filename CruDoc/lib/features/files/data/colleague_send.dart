import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/file_offers_repository.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/lan/device_registry_service.dart';
import 'package:doctor_management_app/features/files/lan/lan_client.dart';
import 'package:doctor_management_app/features/files/lan/lan_device_model.dart';
import 'package:doctor_management_app/features/files/lan/lan_server.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Why [m] can't receive files for [patient], or null when they can.
String? colleagueBlockReason(ClinicMember m, {Patient? patient}) {
  if (!m.active) return 'Not in the clinic';
  if (!m.perms.contains(ClinicPermission.clinicalView)) {
    return "Can't receive patient files";
  }
  if (!m.perms.contains(ClinicPermission.clinicalEdit)) {
    return "Can't save files";
  }
  final scoped =
      ClinicSession.instance.access?.clinicalAccessScope == 'assigned';
  if (scoped && m.kind == MemberKind.doctor) {
    final assigned = patient?.assignedDoctorUids ?? const [];
    if (assigned.isNotEmpty && !assigned.contains(m.uid)) {
      return 'Not assigned to this patient';
    }
  }
  return null;
}

/// A Wi-Fi-only send found no device of the colleague answering here.
class NotOnWifiException extends FilesException {
  const NotOnWifiException(String name) : super('$name is not on this Wi-Fi');
}

/// The device of [colleagueUid] that answers on this Wi-Fi, with its
/// handshake details, or null when none does.
Future<
  ({
    LanDevice peer,
    ({String ip, int port, String nonce, String deviceId}) probe,
  })?
>
findColleagueOnWifi({
  required String clinicId,
  required String colleagueUid,
}) async {
  final peer = await DeviceRegistryService.instance.findColleagueDevice(
    clinicId: clinicId,
    colleagueUid: colleagueUid,
  );
  if (peer == null) return null;
  final probe = await LanClient.instance.probePeer(peer);
  if (probe == null) return null;
  return (peer: peer, probe: probe);
}

/// Sends [files] to [colleague]: direct on clinic Wi-Fi when one of their
/// devices answers, otherwise through the cloud. With [wifiOnly] (the
/// desktop colleague strip) it is always a Wi-Fi offer: when the colleague
/// isn't on this Wi-Fi it waits, and arrives once both devices are
/// ([WifiOffers]). Returns the offers made (Undo cancels them).
Future<List<FileOffer>> sendFilesToColleague({
  required String clinicId,
  required ClinicMember colleague,
  required List<PatientFile> files,
  String subject = '',
  String note = '',
  bool wifiOnly = false,
}) async {
  var via = FileOfferVia.cloud;
  final found = await findColleagueOnWifi(
    clinicId: clinicId,
    colleagueUid: colleague.uid,
  );
  final peer = found?.peer;
  final probe = found?.probe;
  String? token;
  if (peer != null && probe != null) {
    token = await LanClient.instance.createSession(
      peerIp: probe.ip,
      peerPort: probe.port,
      peerCertSha256: peer.certSha256,
      peerDeviceId: probe.deviceId,
      nonce: probe.nonce,
    );
    if (token != null) via = FileOfferVia.lan;
  }
  final postNow = via == FileOfferVia.lan;
  if (wifiOnly) via = FileOfferVia.lan;

  // An offer names the file by fingerprint (the rules refuse one without):
  // files added before fingerprints get one, and a shared copy, first.
  final ready = [
    for (final f in files) await FilesRepository.instance.ensureFingerprint(f),
  ];

  final offers = await FileOffersRepository.instance.createOffers(
    clinicId: clinicId,
    recipientUid: colleague.uid,
    files: ready,
    via: via,
    subject: subject,
    note: note,
  );

  if (via == FileOfferVia.lan) {
    for (final offer in offers) {
      LanServer.instance.registerOpenOffer(offer);
      if (!postNow) continue;
      await LanClient.instance.sendOfferOverLan(
        peerIp: probe!.ip,
        peerPort: probe.port,
        peerCertSha256: peer!.certSha256,
        sessionToken: token!,
        offer: offer,
      );
    }
  }
  return offers;
}

/// Cancels [offers] (the snackbar's Undo). Errors are ignored: an offer
/// already accepted can't be cancelled.
Future<void> undoSend(List<FileOffer> offers) async {
  for (final o in offers) {
    try {
      await FileOffersRepository.instance.cancelOffer(o);
      LanServer.instance.unregisterOpenOffer(o.id);
    } catch (_) {}
  }
}
