import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/core/update/models/app_release.dart';
import 'package:doctor_management_app/core/update/models/update_progress.dart';
import 'package:doctor_management_app/core/update/platform/update_installer.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';

/// iOS's [UpdateInstaller] — written against the interface now, but
/// **not** wired into [UpdateInstallerFactory] yet. Architecture doc §5:
/// "iOS (later, not built now)." Scope is Windows + Android only for
/// this release; this class exists so that when iOS distribution is
/// actually scoped in, the entire change is one branch in the factory
/// — nothing here, in [UpdateService], or in `features/update/*` needs
/// to move.
///
/// Apple doesn't allow installing arbitrary binaries outside the App
/// Store/TestFlight, so this never downloads anything: [download] and
/// [verifyChecksum] are effectively no-ops, and [install] just opens
/// the store/TestFlight URL carried in `update.json`'s
/// `platforms.ios.url` via `url_launcher` (already a dependency).
class IosUpdateInstaller implements UpdateInstaller {
  static const String _platformKey = 'ios';

  Uri? _storeUri;

  @override
  bool get supportsInAppInstall => false;

  @override
  Future<void> download(AppRelease release, void Function(UpdateProgress progress) onProgress) async {
    final url = release.manifest?.platformFor(_platformKey)?.url;
    if (url == null || url.isEmpty) {
      throw const UpdateDownloadException(
        'This release has no iOS App Store/TestFlight URL listed in '
        'update.json (platforms.ios.url).',
      );
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw const UpdateDownloadException('The iOS update URL in update.json could not be parsed.');
    }

    _storeUri = uri;
    // There's no byte-for-byte download to report progress on — jump
    // straight to "ready" so UpdateProgressSheet doesn't sit on an
    // indeterminate downloading spinner for something that isn't downloading.
    onProgress(const UpdateProgress(state: UpdateProgressState.readyToInstall));
  }

  @override
  Future<bool> verifyChecksum() async => true;

  @override
  Future<void> install() async {
    final uri = _storeUri;
    if (uri == null) {
      throw const UpdateInstallException('No App Store/TestFlight URL to open.');
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw const UpdateInstallException('Could not open the App Store/TestFlight link.');
    }
  }
}
