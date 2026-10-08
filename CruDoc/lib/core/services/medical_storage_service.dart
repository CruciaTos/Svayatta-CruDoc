import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/features/files/data/file_types.dart';

import '../errors/storage_exceptions.dart';
import 'access_audit_service.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';

export '../errors/storage_exceptions.dart';

/// What kind of clinical file is being stored for a patient.
enum ClinicalMediaKind {
  xray('xrays'),
  photo('photos'),
  lab('labs'),

  /// Diagnostic originals (DICOM, TIFF) from the radiology module.
  imaging('imaging'),

  /// Small JPEG previews of [imaging] originals, for lists and thumbnails.
  imagingPreview('imaging-previews');

  const ClinicalMediaKind(this.folder);
  final String folder;
}

/// Which clinic branding image is being stored.
enum ClinicBrandingKind {
  logo('logo'),
  signature('signature');

  const ClinicBrandingKind(this.fileName);
  final String fileName;
}

/// Where an uploaded file landed.
class StoredFile {
  const StoredFile({
    required this.path,
    required this.contentType,
    required this.sizeBytes,
  });

  /// Full object path in the bucket; save this, not a download URL.
  final String path;
  final String contentType;
  final int sizeBytes;
}

/// Uploads, downloads and deletes the doctor's files in Firebase Cloud
/// Storage.
///
/// Every file is owned by the signed-in doctor. Permanent patient files go
/// to `doctors/{doctorId}/patients/{patientId}/{category}/{YYYY}/{MM}/{fileId}.{ext}`;
/// clinic-level files to `doctors/{doctorId}/{category}/...`; files added
/// on the Files screen to `patient-files/{doctorId}/{patientId}/{fileId}/original`;
/// voice dictation awaiting transcription to
/// `voice-scratch/doctors/{doctorId}/patients/{patientId}/{uuid}.m4a`.
///
/// The size cap and content types mirror storage.rules — keep them in sync.
class MedicalStorageService {
  MedicalStorageService._();

  static final MedicalStorageService instance = MedicalStorageService._();

  static const int maxUploadBytes = 15 * 1024 * 1024;

  /// DICOM and TIFF originals are allowed more (storage.rules matches).
  static const int maxImagingUploadBytes = 250 * 1024 * 1024;

  /// The size limit storage.rules applies to a file of [contentType].
  static int maxUploadBytesFor(String contentType) =>
      _imagingTypes.contains(contentType)
      ? maxImagingUploadBytes
      : maxUploadBytes;

  /// Photos are scaled to fit this box (rotated for portrait shots) and
  /// re-encoded as JPEG at [_jpegQuality].
  static const int _maxLongEdge = 1920;
  static const int _maxShortEdge = 1080;
  static const int _jpegQuality = 85;

  static const String _jpeg = 'image/jpeg';
  static const String _png = 'image/png';
  static const String _webp = 'image/webp';
  static const String _pdf = 'application/pdf';
  static const String _csv = 'text/csv';
  static const String _binary = 'application/octet-stream';
  static const String _m4a = 'audio/mp4';
  static const String _dicom = 'application/dicom';
  static const String _tiff = 'image/tiff';

  static const Set<String> _imageTypes = {_jpeg, _png, _webp};
  static const Set<String> _audioTypes = {_m4a, 'audio/aac', 'audio/opus'};
  static const Set<String> _imagingTypes = {_dicom, _tiff};

  static const Map<String, String> _extensions = {
    _jpeg: 'jpg',
    _png: 'png',
    _webp: 'webp',
    _pdf: 'pdf',
    _csv: 'csv',
    _binary: 'enc',
    _dicom: 'dcm',
    _tiff: 'tif',
    _m4a: 'm4a',
    'audio/aac': 'aac',
    'audio/opus': 'opus',
  };

  FirebaseStorage get _storage => FirebaseStorage.instance;
  static const Uuid _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // Patient files
  // ---------------------------------------------------------------------------

  Future<StoredFile> uploadPatientAvatar({
    required String doctorId,
    required String patientId,
    required Uint8List bytes,
    required String contentType,
  }) {
    _requireImage(contentType);
    return _uploadPatientFile(
      doctorId: doctorId,
      patientId: patientId,
      category: 'avatar',
      bytes: bytes,
      contentType: contentType,
      compress: true,
    );
  }

  Future<StoredFile> uploadPrescriptionPdf({
    required String doctorId,
    required String patientId,
    required Uint8List bytes,
  }) => _uploadPatientFile(
    doctorId: doctorId,
    patientId: patientId,
    category: 'prescriptions',
    bytes: bytes,
    contentType: _pdf,
  );

  Future<StoredFile> uploadInvoicePdf({
    required String doctorId,
    required String patientId,
    required Uint8List bytes,
  }) => _uploadPatientFile(
    doctorId: doctorId,
    patientId: patientId,
    category: 'invoices',
    bytes: bytes,
    contentType: _pdf,
  );

  Future<StoredFile> uploadTreatmentPlanPdf({
    required String doctorId,
    required String patientId,
    required Uint8List bytes,
  }) => _uploadPatientFile(
    doctorId: doctorId,
    patientId: patientId,
    category: 'treatment-plans',
    bytes: bytes,
    contentType: _pdf,
  );

  /// X-rays, clinical photos and lab reports. Images are compressed unless
  /// [compress] is false — pass false to keep a diagnostic original at full
  /// resolution. PDFs (typically lab reports) are stored as-is.
  Future<StoredFile> uploadClinicalMedia({
    required String doctorId,
    required String patientId,
    required ClinicalMediaKind kind,
    required Uint8List bytes,
    required String contentType,
    bool compress = true,
  }) {
    _requireOneOf(contentType, {..._imageTypes, _pdf});
    return _uploadPatientFile(
      doctorId: doctorId,
      patientId: patientId,
      category: 'clinical/${kind.folder}',
      bytes: bytes,
      contentType: contentType,
      compress: compress && _imageTypes.contains(contentType),
    );
  }

  /// A diagnostic original (DICOM or TIFF), stored byte for byte under
  /// `clinical/imaging`. Up to [maxImagingUploadBytes].
  Future<StoredFile> uploadImagingOriginal({
    required String doctorId,
    required String patientId,
    required Uint8List bytes,
    required String contentType,
  }) {
    _requireOneOf(contentType, _imagingTypes);
    return _uploadPatientFile(
      doctorId: doctorId,
      patientId: patientId,
      category: 'clinical/${ClinicalMediaKind.imaging.folder}',
      bytes: bytes,
      contentType: contentType,
    );
  }

  /// A file added on the Files screen, stored byte for byte. Kept outside
  /// `doctors/` so who may read it follows the file's own record (its
  /// folder's sharing) rather than the clinic-wide patient-file rule. The
  /// object has no extension (the content type is in its metadata), so no
  /// lifecycle rule keyed on a suffix ever deletes it.
  Future<StoredFile> uploadPatientFile({
    required String doctorId,
    required String patientId,
    required String fileId,
    required Uint8List bytes,
    required String contentType,
  }) {
    _requireSignedInAs(doctorId);
    _requireOneOf(contentType, PatientFileTypes.contentTypes);
    final path =
        'patient-files/$doctorId/${_segment(patientId)}/${_segment(fileId)}/original';
    return _put(
      path,
      bytes,
      contentType,
      {'doctorId': doctorId, 'patientId': patientId, 'category': 'files'},
      limit: PatientFileTypes.maxBytesFor(contentType),
    );
  }

  /// Voice dictation for transcription. Stored under `voice-scratch/`, which
  /// is write-once: each call creates a new object and nothing overwrites it.
  /// Delete it with [delete] once the transcript is saved.
  Future<StoredFile> uploadVoiceDictation({
    required String doctorId,
    required String patientId,
    required Uint8List bytes,
    String contentType = _m4a,
  }) {
    _requireSignedInAs(doctorId, personal: true);
    _requireOneOf(contentType, _audioTypes);
    final path =
        'voice-scratch/doctors/$doctorId/patients/${_segment(patientId)}/'
        '${_uuid.v4()}.${_extensions[contentType]}';
    return _put(path, bytes, contentType, {
      'doctorId': doctorId,
      'patientId': patientId,
      'category': 'voice-dictation',
    });
  }

  // ---------------------------------------------------------------------------
  // Clinic files
  // ---------------------------------------------------------------------------

  /// Clinic logo or signature. Kept at a fixed name so a new upload replaces
  /// the old one. PNGs are stored untouched to keep transparency; other
  /// images are compressed to JPEG.
  Future<StoredFile> uploadClinicBranding({
    required String doctorId,
    required ClinicBrandingKind kind,
    required Uint8List bytes,
    required String contentType,
  }) async {
    _requireSignedInAs(doctorId);
    _requireImage(contentType);
    final keepAsIs = contentType == _png;
    final payload = keepAsIs ? bytes : await _compress(bytes);
    final type = keepAsIs ? _png : _jpeg;
    final path =
        'doctors/$doctorId/clinic/branding/${kind.fileName}.${_extensions[type]}';
    return _put(path, payload, type, {
      'doctorId': doctorId,
      'category': 'branding',
    });
  }

  /// Supplier bill or receipt for stock intake: a photo or a PDF.
  Future<StoredFile> uploadInventoryReceipt({
    required String doctorId,
    required Uint8List bytes,
    required String contentType,
  }) {
    _requireOneOf(contentType, {..._imageTypes, _pdf});
    return _uploadClinicFile(
      doctorId: doctorId,
      category: 'inventory-receipts',
      bytes: bytes,
      contentType: contentType,
      compress: _imageTypes.contains(contentType),
    );
  }

  /// Photo of an autoclave indicator strip for the sterilization log.
  Future<StoredFile> uploadSterilizationStrip({
    required String doctorId,
    required Uint8List bytes,
    required String contentType,
  }) {
    _requireImage(contentType);
    return _uploadClinicFile(
      doctorId: doctorId,
      category: 'sterilization-strips',
      bytes: bytes,
      contentType: contentType,
      compress: true,
    );
  }

  /// An already-encrypted local database backup (`.enc`).
  Future<StoredFile> uploadDatabaseBackup({
    required String doctorId,
    required Uint8List encryptedBytes,
  }) => _uploadClinicFile(
    doctorId: doctorId,
    category: 'backups',
    bytes: encryptedBytes,
    contentType: _binary,
  );

  Future<StoredFile> uploadRevenueCsv({
    required String doctorId,
    required Uint8List bytes,
  }) => _uploadClinicFile(
    doctorId: doctorId,
    category: 'exports/revenue',
    bytes: bytes,
    contentType: _csv,
  );

  // ---------------------------------------------------------------------------
  // Reading, deleting, listing
  // ---------------------------------------------------------------------------

  /// A long-lived URL that anyone holding it can open, bypassing
  /// storage.rules. Prefer [downloadBytes] for patient records; use this
  /// only where a URL is unavoidable (e.g. an image widget) and never
  /// persist or share it.
  Future<String> getDownloadUrl(String storagePath) {
    _requireOwnedPath(storagePath);
    AccessAuditService.instance.fileDownloaded(storagePath);
    return _storage.ref(storagePath).getDownloadURL();
  }

  Future<Uint8List> downloadBytes(String storagePath) async {
    _requireOwnedPath(storagePath);
    AccessAuditService.instance.fileDownloaded(storagePath);
    final data = await _storage.ref(storagePath).getData(maxImagingUploadBytes);
    if (data == null) {
      throw StateError('No data found at $storagePath.');
    }
    return data;
  }

  /// Writes the file to [destination]. Not available on web.
  Future<File> downloadToFile(String storagePath, File destination) async {
    if (kIsWeb) {
      throw UnsupportedError('downloadToFile is not supported on web.');
    }
    _requireOwnedPath(storagePath);
    AccessAuditService.instance.fileDownloaded(storagePath);
    await _storage.ref(storagePath).writeToFile(destination);
    return destination;
  }

  Future<void> delete(String storagePath) {
    _requireOwnedPath(storagePath);
    return _storage.ref(storagePath).delete();
  }

  /// Every file stored for a patient, optionally limited to one category
  /// (e.g. `prescriptions`, `clinical/xrays`).
  Future<List<Reference>> listPatientFiles({
    required String doctorId,
    required String patientId,
    String? category,
  }) {
    _requireSignedInAs(doctorId);
    var prefix = 'doctors/$doctorId/patients/${_segment(patientId)}';
    if (category != null) prefix = '$prefix/$category';
    return _listRecursive(_storage.ref(prefix));
  }

  /// Every file under [storagePath], including nested year/month folders.
  Future<List<Reference>> listFolder(String storagePath) {
    _requireOwnedPath(storagePath);
    return _listRecursive(_storage.ref(storagePath));
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<StoredFile> _uploadPatientFile({
    required String doctorId,
    required String patientId,
    required String category,
    required Uint8List bytes,
    required String contentType,
    bool compress = false,
  }) {
    _requireSignedInAs(doctorId);
    return _uploadDated(
      folder: 'doctors/$doctorId/patients/${_segment(patientId)}/$category',
      bytes: bytes,
      contentType: contentType,
      compress: compress,
      metadata: {
        'doctorId': doctorId,
        'patientId': patientId,
        'category': category,
      },
    );
  }

  Future<StoredFile> _uploadClinicFile({
    required String doctorId,
    required String category,
    required Uint8List bytes,
    required String contentType,
    bool compress = false,
  }) {
    _requireSignedInAs(doctorId);
    return _uploadDated(
      folder: 'doctors/$doctorId/$category',
      bytes: bytes,
      contentType: contentType,
      compress: compress,
      metadata: {'doctorId': doctorId, 'category': category},
    );
  }

  /// Uploads to `{folder}/{YYYY}/{MM}/{fileId}.{ext}`.
  Future<StoredFile> _uploadDated({
    required String folder,
    required Uint8List bytes,
    required String contentType,
    required bool compress,
    required Map<String, String> metadata,
  }) async {
    final payload = compress ? await _compress(bytes) : bytes;
    final type = compress ? _jpeg : contentType;
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final path =
        '$folder/${now.year}/$month/${_uuid.v4()}.${_extensions[type]}';
    return _put(path, payload, type, metadata);
  }

  Future<StoredFile> _put(
    String path,
    Uint8List bytes,
    String contentType,
    Map<String, String> metadata, {
    int? limit,
  }) async {
    limit ??= maxUploadBytesFor(contentType);
    if (bytes.lengthInBytes > limit) {
      throw StorageFileTooLargeException(bytes.lengthInBytes, limit);
    }
    await _storage
        .ref(path)
        .putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            cacheControl: 'private, max-age=3600',
            customMetadata: metadata,
          ),
        );
    return StoredFile(
      path: path,
      contentType: contentType,
      sizeBytes: bytes.lengthInBytes,
    );
  }

  Future<Uint8List> _compress(Uint8List bytes) async {
    try {
      return await compute(_compressToJpeg, bytes);
    } catch (_) {
      throw const StorageCompressionException();
    }
  }

  Future<List<Reference>> _listRecursive(Reference folder) async {
    final result = await folder.listAll();
    final nested = await Future.wait(result.prefixes.map(_listRecursive));
    return [...result.items, for (final refs in nested) ...refs];
  }

  /// [doctorId] is the clinic for `doctors/…` files; for the voice
  /// dictation scratch folder ([personal]) it is the signed-in person.
  void _requireSignedInAs(String doctorId, {bool personal = false}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const StorageAuthException(
        'You must be signed in to access files.',
      );
    }
    final expected = personal ? uid : ClinicSession.instance.tenantId;
    if (expected != doctorId) throw const StorageAuthException();
  }

  /// Checks [storagePath] sits inside the signed-in doctor's own folders.
  void _requireOwnedPath(String storagePath) {
    final parts = storagePath.split('/');
    final doctorId = switch (parts) {
      ['doctors', final id, _, ...] => id,
      ['voice-scratch', 'doctors', final id, _, ...] => id,
      ['patient-files', final id, _, ...] => id,
      _ => null,
    };
    if (doctorId == null || parts.any((p) => p.isEmpty || p == '..')) {
      throw ArgumentError.value(
        storagePath,
        'storagePath',
        'Not a doctor file path',
      );
    }
    _requireSignedInAs(doctorId, personal: parts.first == 'voice-scratch');
  }

  /// Rejects ids that would break out of their path segment.
  String _segment(String id) {
    if (id.isEmpty || id.contains('/') || id == '.' || id == '..') {
      throw ArgumentError.value(id, 'id', 'Must be a single path segment');
    }
    return id;
  }

  void _requireImage(String contentType) =>
      _requireOneOf(contentType, _imageTypes);

  void _requireOneOf(String contentType, Set<String> allowed) {
    if (!allowed.contains(contentType)) {
      throw ArgumentError.value(
        contentType,
        'contentType',
        'Expected one of ${allowed.join(', ')}',
      );
    }
  }
}

/// Top-level so it can run on a background isolate via [compute].
Uint8List _compressToJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image format');
  }
  var image = img.bakeOrientation(decoded);

  final landscape = image.width >= image.height;
  final maxWidth = landscape
      ? MedicalStorageService._maxLongEdge
      : MedicalStorageService._maxShortEdge;
  final maxHeight = landscape
      ? MedicalStorageService._maxShortEdge
      : MedicalStorageService._maxLongEdge;
  if (image.width > maxWidth || image.height > maxHeight) {
    final scale = math.min(maxWidth / image.width, maxHeight / image.height);
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
  return img.encodeJpg(image, quality: MedicalStorageService._jpegQuality);
}
