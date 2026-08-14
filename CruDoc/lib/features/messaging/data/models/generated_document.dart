import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/errors/gmail_exceptions.dart';

/// Document or file attachment model for email messages.
///
/// Implements rigorous defensive sanitization:
/// - Enforces a maximum 20MB file size limit (Gmail API request limit is 25MB).
/// - Sanitizes filenames against path traversal (`..`, `/`, `\`), CRLF injection, and quotes.
/// - Validates MIME types against safe formats.
@immutable
class GeneratedDocument {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  GeneratedDocument({
    required this.bytes,
    required String fileName,
    String mimeType = 'application/pdf',
  })  : fileName = _sanitizeFileName(fileName),
        mimeType = _validateMimeType(mimeType) {
    if (bytes.isEmpty) {
      throw const GmailValidationException('Attachment cannot be empty (0 bytes).');
    }
    if (bytes.lengthInBytes > maxSizeBytes) {
      throw GmailValidationException(
        'Attachment "$fileName" exceeds the maximum allowed size of 20MB.',
      );
    }
  }

  /// Maximum file size allowed: 20MB.
  static const int maxSizeBytes = 20 * 1024 * 1024;

  static const Set<String> _allowedMimeTypes = {
    'application/pdf',
    'image/png',
    'image/jpeg',
    'image/jpg',
    'text/plain',
    'text/csv',
    'application/octet-stream',
  };

  /// Sanitizes attachment filenames against path traversal, control characters, and injection.
  static String _sanitizeFileName(String name) {
    var clean = name.trim();
    // Remove directory traversal characters
    clean = clean.replaceAll(RegExp(r'[/\\]'), '_');
    // Remove control characters (including CRLF)
    clean = clean.replaceAll(RegExp(r'[\r\n\x00-\x1F\x7F]'), '');
    // Remove quotes
    clean = clean.replaceAll(RegExp(r'["'']'), '');
    // Remove leading dots
    clean = clean.replaceFirst(RegExp(r'^\.+'), '');

    if (clean.isEmpty) {
      clean = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
    }

    // Limit filename length to 255 characters
    if (clean.length > 255) {
      final extIndex = clean.lastIndexOf('.');
      if (extIndex != -1 && clean.length - extIndex <= 10) {
        final ext = clean.substring(extIndex);
        clean = clean.substring(0, 255 - ext.length) + ext;
      } else {
        clean = clean.substring(0, 255);
      }
    }

    return clean;
  }

  static String _validateMimeType(String mime) {
    final lower = mime.trim().toLowerCase();
    if (_allowedMimeTypes.contains(lower)) {
      return lower;
    }
    return 'application/octet-stream';
  }
}
