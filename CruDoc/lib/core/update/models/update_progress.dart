/// Lifecycle of an in-flight [UpdateService.startDownloadAndInstall]
/// run. `UpdateProgressSheet` switches on this directly, so the order
/// and names here must stay exactly as `features/update/presentation`
/// already expects.
enum UpdateProgressState {
  idle,
  downloading,
  verifying,
  readyToInstall,
  installing,
  failed,
}

/// Snapshot of an in-flight download/verify/install, streamed by
/// [UpdateService.startDownloadAndInstall] and watched via
/// `updateProgressProvider`.
class UpdateProgress {
  final UpdateProgressState state;

  /// Bytes downloaded so far. Only meaningful while [state] is
  /// [UpdateProgressState.downloading]; `0` otherwise.
  final int bytesDownloaded;

  /// Total bytes expected, from the HTTP response's content-length or
  /// the size recorded in `update.json`/the release asset. `0` means
  /// unknown — `UpdateProgressSheet` falls back to an indeterminate bar.
  final int totalBytes;

  /// `bytesDownloaded / totalBytes`, clamped to `[0, 1]`. `0` when
  /// [totalBytes] is unknown.
  final double percent;

  /// Short, user-presentable failure reason. Only set when
  /// [state] is [UpdateProgressState.failed]; not part of the minimal
  /// contract `features/update` was written against, but available for
  /// a future "show why it failed" UI without a shape change.
  final String? errorMessage;

  const UpdateProgress({
    required this.state,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.percent = 0,
    this.errorMessage,
  });

  static const idleState = UpdateProgress(state: UpdateProgressState.idle);

  @override
  String toString() => 'UpdateProgress($state, $bytesDownloaded/$totalBytes)';
}
