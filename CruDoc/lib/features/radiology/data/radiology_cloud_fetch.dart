import 'dart:io';

import 'package:doctor_management_app/core/services/medical_storage_service.dart';

/// Downloads radiology files from Cloud Storage into a study's folder the
/// first time they are needed on this computer.
///
/// Each image is its own object, so opening a study fetches only the
/// images actually looked at, one at a time, rather than the whole study.
/// Concurrent requests for the same file share one download, and a file
/// appears at its final path only once it is complete.
class RadCloudFetch {
  RadCloudFetch({
    Future<void> Function(String storagePath, File destination)? download,
  }) : _download = download ?? _viaStorageService;

  static final RadCloudFetch instance = RadCloudFetch();

  final Future<void> Function(String storagePath, File destination) _download;
  final Map<String, Future<File>> _inFlight = {};

  /// [destination], downloaded from [storagePath] unless already there.
  Future<File> fetch(String storagePath, File destination) {
    final key = destination.path;
    // A block body: returning the removed future from the callback would make
    // whenComplete wait on itself.
    return _inFlight[key] ??= _fetch(storagePath, destination).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<File> _fetch(String storagePath, File destination) async {
    if (await destination.exists()) return destination;
    await destination.parent.create(recursive: true);
    final part = File('${destination.path}.part');
    try {
      await _download(storagePath, part);
      return await part.rename(destination.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  static Future<void> _viaStorageService(
    String storagePath,
    File destination,
  ) => MedicalStorageService.instance.downloadToFile(storagePath, destination);
}
