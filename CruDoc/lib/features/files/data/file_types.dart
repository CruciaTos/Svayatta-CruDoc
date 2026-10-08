import 'package:path/path.dart' as p;

/// What kind of file a stored file is, for its icon, its filter chip and
/// how it opens.
enum FileKind {
  image('Images'),
  pdf('PDFs'),
  scan('Scans'),
  document('Documents'),
  video('Videos'),
  audio('Audio');

  const FileKind(this.label);

  /// Filter chip label.
  final String label;
}

/// The file types the Files screen takes, and how large they may be.
///
/// Mirrors the `patient-files/` match in storage.rules: keep the content
/// types and size limits in step with it. Anything that could run on its
/// own (programs, scripts, archives) is left out on purpose.
abstract final class PatientFileTypes {
  static const int mb = 1024 * 1024;

  /// Most files.
  static const int maxBytes = 50 * mb;

  /// DICOM and TIFF originals, which are often large.
  static const int maxImagingBytes = 250 * mb;

  static const String dicom = 'application/dicom';
  static const String tiff = 'image/tiff';

  /// Extension → content type. The one place extensions are mapped.
  static const Map<String, String> _byExtension = {
    // Pictures and X-rays.
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'tif': tiff,
    'tiff': tiff,
    'dcm': dicom,
    'dicom': dicom,
    // 3D scans (intraoral, models).
    'stl': 'model/stl',
    'ply': 'model/ply',
    'obj': 'model/obj',
    // Reports and documents.
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'rtf': 'application/rtf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    // Video and audio.
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
  };

  /// Every content type the Files screen uploads (storage.rules matches).
  static final Set<String> contentTypes = _byExtension.values.toSet();

  /// The content type for [fileName], or null when it isn't a type the
  /// Files screen takes.
  static String? contentTypeFor(String fileName) {
    final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
    return _byExtension[ext];
  }

  static int maxBytesFor(String contentType) =>
      contentType == dicom || contentType == tiff ? maxImagingBytes : maxBytes;

  static FileKind kindOf(String contentType) {
    if (contentType == dicom || contentType.startsWith('model/')) {
      return FileKind.scan;
    }
    if (contentType == tiff || contentType.startsWith('image/')) {
      return FileKind.image;
    }
    if (contentType == 'application/pdf') return FileKind.pdf;
    if (contentType.startsWith('video/')) return FileKind.video;
    if (contentType.startsWith('audio/')) return FileKind.audio;
    return FileKind.document;
  }

  /// Pictures Flutter can draw itself (thumbnails and the in-app viewer).
  static bool isViewableImage(String contentType) => const {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/bmp',
  }.contains(contentType);

  /// "4.2 MB", "820 KB".
  static String sizeLabel(int bytes) {
    if (bytes >= mb) {
      final v = bytes / mb;
      return '${v >= 10 ? v.round() : v.toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}
