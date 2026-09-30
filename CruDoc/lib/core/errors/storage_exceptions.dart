/// Base type for every error thrown by `MedicalStorageService`. Lets calling
/// code catch all of them generically, or a specific subtype when it needs
/// to react differently.
sealed class MedicalStorageException implements Exception {
  final String message;
  const MedicalStorageException(this.message);

  @override
  String toString() => message;
}

/// No doctor is signed in, or the signed-in doctor is not the owner of the
/// requested files. Storage rules would reject the request anyway; this
/// fails fast on the client with a clear message instead.
class StorageAuthException extends MedicalStorageException {
  const StorageAuthException([
    super.message =
        'You must be signed in as the owning doctor to access these files.',
  ]);
}

/// The file (after any compression) is larger than the upload cap.
class StorageFileTooLargeException extends MedicalStorageException {
  final int sizeBytes;
  final int maxBytes;

  StorageFileTooLargeException(this.sizeBytes, this.maxBytes)
    : super(
        'File is ${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB; '
        'the limit is ${maxBytes ~/ (1024 * 1024)} MB.',
      );
}

/// The image could not be decoded or re-encoded before upload.
class StorageCompressionException extends MedicalStorageException {
  const StorageCompressionException([
    super.message =
        'This image could not be processed. Try a JPEG, PNG or WebP file.',
  ]);
}
