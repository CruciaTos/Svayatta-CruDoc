import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/files/data/file_fingerprint.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'device_identity.dart';
import 'lan_device_model.dart';
import 'lan_ip_helper.dart';

/// Progress information for an active file transfer.
@immutable
class TransferProgress {
  const TransferProgress({
    required this.offerId,
    required this.fileName,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.bytesPerSecond,
    this.isDone = false,
    this.error,
  });

  final String offerId;
  final String fileName;
  final int bytesTransferred;
  final int totalBytes;
  final double bytesPerSecond;
  final bool isDone;
  final String? error;

  double get fraction => totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;
  int get percent => (fraction * 100).round();
}

/// Discovers, authenticates, and transfers files directly over LAN with 8MB chunked resume (Tasks N3, N4).
class LanClient {
  LanClient._();
  static final LanClient instance = LanClient._();

  static const int chunkSize = 8 * 1024 * 1024; // 8 MB chunks
  static const Duration probeTimeout = Duration(milliseconds: 1500);

  final Map<String, bool> _activeTransfers = {};

  /// Creates an [HttpClient] pinned strictly to the peer's [certSha256].
  HttpClient _createPinnedClient(String peerCertSha256) {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      final sha = sha256.convert(cert.der).toString().toLowerCase();
      final expected = peerCertSha256.toLowerCase();
      return sha == expected;
    };
    return client;
  }

  /// Probes candidate IPs of a colleague's device in parallel with a 1.5-second timeout.
  /// Returns the first responsive IP and handshake details, or null.
  Future<({String ip, int port, String nonce, String deviceId})?> probePeer(
    LanDevice peer,
  ) async {
    if (!peer.hasLanEndpoint) return null;

    final myIps = await LanIpHelper.getLocalIpv4Addresses();
    final candidateIps = LanIpHelper.matchingSubnetIps(myIps: myIps, peerIps: peer.ips);
    final ipsToTry = candidateIps.isNotEmpty ? candidateIps : peer.ips;

    final client = _createPinnedClient(peer.certSha256);

    final futures = ipsToTry.map((ip) async {
      try {
        final uri = Uri.parse('https://$ip:${peer.port}/v1/hello');
        final request = await client.getUrl(uri).timeout(probeTimeout);
        final response = await request.close().timeout(probeTimeout);

        if (response.statusCode == HttpStatus.ok) {
          final bodyStr = await utf8.decoder.bind(response).join();
          final data = jsonDecode(bodyStr) as Map<String, dynamic>;
          final nonce = data['nonce'] as String? ?? '';
          final deviceId = data['deviceId'] as String? ?? '';

          if (nonce.isNotEmpty && deviceId == peer.id) {
            return (ip: ip, port: peer.port, nonce: nonce, deviceId: deviceId);
          }
        }
      } catch (_) {}
      return null;
    });

    try {
      final results = await Future.wait(futures);
      return results.where((r) => r != null).firstOrNull;
    } finally {
      client.close(force: true);
    }
  }

  /// Performs mutual authentication handshake and returns a 15-minute session token.
  Future<String?> createSession({
    required String peerIp,
    required int peerPort,
    required String peerCertSha256,
    required String peerDeviceId,
    required String nonce,
  }) async {
    final client = _createPinnedClient(peerCertSha256);
    try {
      final sigBase64 = DeviceIdentity.instance.signChallenge(
        serverDeviceId: peerDeviceId,
        nonce: nonce,
        clientCertSha256: DeviceIdentity.instance.certSha256,
      );

      final uri = Uri.parse('https://$peerIp:$peerPort/v1/session');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      request.write(jsonEncode({
        'deviceId': DeviceIdentity.instance.deviceId,
        'nonce': nonce,
        'signature': sigBase64,
      }));

      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final bodyStr = await utf8.decoder.bind(response).join();
        final data = jsonDecode(bodyStr) as Map<String, dynamic>;
        return data['token'] as String?;
      }
    } catch (e) {
      debugPrint('[LanClient] Session creation error: $e');
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Sends a file offer directly to the peer over the established LAN session.
  Future<bool> sendOfferOverLan({
    required String peerIp,
    required int peerPort,
    required String peerCertSha256,
    required String sessionToken,
    required FileOffer offer,
  }) async {
    final client = _createPinnedClient(peerCertSha256);
    try {
      final uri = Uri.parse('https://$peerIp:$peerPort/v1/offers');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sessionToken');

      request.write(jsonEncode(offer.toJson()));
      final response = await request.close();
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint('[LanClient] Send offer error: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Pulls the file bytes from the sender in 8MB chunks with resume support.
  Stream<TransferProgress> pullBlob({
    required String senderIp,
    required int senderPort,
    required String senderCertSha256,
    required String sessionToken,
    required FileOffer offer,
  }) async* {
    final offerId = offer.id;
    _activeTransfers[offerId] = true;

    final tempDir = await getApplicationSupportDirectory();
    final inboxDir = Directory('${tempDir.path}/lan_inbox');
    if (!await inboxDir.exists()) await inboxDir.create(recursive: true);

    final partFile = File('${inboxDir.path}/$offerId.part');
    var downloadedBytes = 0;
    if (await partFile.exists()) {
      downloadedBytes = await partFile.length();
    }

    final totalBytes = offer.sizeBytes;
    final client = _createPinnedClient(senderCertSha256);

    final backoffs = [1, 2, 5, 10, 30];
    int retryIndex = 0;

    DateTime lastTime = DateTime.now();
    int lastBytes = downloadedBytes;

    try {
      while (downloadedBytes < totalBytes && (_activeTransfers[offerId] ?? false)) {
        final chunkEnd = min(downloadedBytes + chunkSize - 1, totalBytes - 1);

        try {
          final uri = Uri.parse('https://$senderIp:$senderPort/v1/blobs/${offer.sha256}');
          final request = await client.getUrl(uri);
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sessionToken');
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$downloadedBytes-$chunkEnd');

          final response = await request.close();
          if (response.statusCode != HttpStatus.partialContent &&
              response.statusCode != HttpStatus.ok) {
            throw HttpException('Unexpected HTTP status: ${response.statusCode}');
          }

          final sink = partFile.openWrite(mode: FileMode.append);
          await for (final piece in response) {
            if (!(_activeTransfers[offerId] ?? false)) {
              await sink.close();
              break;
            }
            sink.add(piece);
            downloadedBytes += piece.length;

            final now = DateTime.now();
            final elapsed = now.difference(lastTime).inMilliseconds / 1000.0;
            if (elapsed >= 0.5) {
              final speed = (downloadedBytes - lastBytes) / elapsed;
              lastTime = now;
              lastBytes = downloadedBytes;
              yield TransferProgress(
                offerId: offerId,
                fileName: offer.name,
                bytesTransferred: downloadedBytes,
                totalBytes: totalBytes,
                bytesPerSecond: speed,
              );
            }
          }
          await sink.flush();
          await sink.close();

          retryIndex = 0; // reset backoff on successful piece
        } catch (e) {
          if (!(_activeTransfers[offerId] ?? false)) break;

          final waitSec = backoffs[min(retryIndex, backoffs.length - 1)];
          retryIndex++;
          debugPrint('[LanClient] Pull error ($e). Retrying in ${waitSec}s...');
          await Future.delayed(Duration(seconds: waitSec));
        }
      }

      if (!(_activeTransfers[offerId] ?? false)) {
        if (await partFile.exists()) await partFile.delete();
        yield TransferProgress(
          offerId: offerId,
          fileName: offer.name,
          bytesTransferred: downloadedBytes,
          totalBytes: totalBytes,
          bytesPerSecond: 0,
          error: 'Transfer cancelled',
        );
        return;
      }

      // Transfer complete - verify SHA-256 fingerprint
      final computedSha = await computeFileSha256(partFile.path);
      if (computedSha.toLowerCase() != offer.sha256.toLowerCase()) {
        if (await partFile.exists()) await partFile.delete();
        yield TransferProgress(
          offerId: offerId,
          fileName: offer.name,
          bytesTransferred: downloadedBytes,
          totalBytes: totalBytes,
          bytesPerSecond: 0,
          error: 'File damaged, SHA-256 mismatch. Please try again.',
        );
        return;
      }

      // Rename to final medical storage path and create received file record
      final destDir = Directory('${tempDir.path}/medical_files');
      if (!await destDir.exists()) await destDir.create(recursive: true);
      final destPath = '${destDir.path}/${offer.fileId}_${offer.name}';
      await partFile.rename(destPath);

      await FilesRepository.instance.createReceivedFile(
        offer: offer,
        localFilePath: destPath,
      );

      // Notify sender of acceptance
      await sendStatus(
        senderIp: senderIp,
        senderPort: senderPort,
        senderCertSha256: senderCertSha256,
        sessionToken: sessionToken,
        offerId: offerId,
        status: 'accepted',
      );

      yield TransferProgress(
        offerId: offerId,
        fileName: offer.name,
        bytesTransferred: totalBytes,
        totalBytes: totalBytes,
        bytesPerSecond: 0,
        isDone: true,
      );
    } finally {
      client.close(force: true);
      _activeTransfers.remove(offerId);
    }
  }

  /// Cancels an in-progress transfer.
  void cancelTransfer(String offerId) {
    _activeTransfers[offerId] = false;
  }

  /// Reports offer status ("accepted" or "declined") to sender.
  Future<void> sendStatus({
    required String senderIp,
    required int senderPort,
    required String senderCertSha256,
    required String sessionToken,
    required String offerId,
    required String status,
  }) async {
    final client = _createPinnedClient(senderCertSha256);
    try {
      final uri = Uri.parse('https://$senderIp:$senderPort/v1/offers/$offerId/status');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sessionToken');
      request.write(jsonEncode({'status': status}));
      await request.close();
    } catch (_) {} finally {
      client.close(force: true);
    }
  }
}
