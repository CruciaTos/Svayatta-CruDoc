import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_sync_queue.dart';

/// Files waiting to upload (or uploading) for the signed-in doctor.
final pendingUploadCountProvider = StreamProvider<int>(
  (ref) => StorageSyncQueue.instance.watchPendingCount(),
);

/// Files that gave up and need the doctor's attention.
final failedUploadCountProvider = StreamProvider<int>(
  (ref) => StorageSyncQueue.instance.watchFailedCount(),
);

/// The failed files themselves, for the "Sync issues" list. Reloads when
/// the failed count changes; invalidate it after a retry or discard.
final failedUploadsProvider = FutureProvider.autoDispose<List<PendingUpload>>((
  ref,
) {
  ref.watch(failedUploadCountProvider);
  return StorageSyncQueue.instance.failedUploads();
});
