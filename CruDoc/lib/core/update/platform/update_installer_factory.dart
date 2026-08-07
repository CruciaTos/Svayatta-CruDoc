import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:doctor_management_app/core/update/platform/android_update_installer.dart';
import 'package:doctor_management_app/core/update/platform/update_installer.dart';
import 'package:doctor_management_app/core/update/platform/windows_update_installer.dart';
import 'package:doctor_management_app/core/update/update_exceptions.dart';

/// The **only** class in the entire update framework that branches on
/// `Platform.isX` — design principle #3. [UpdateService] and everything
/// above it only ever see the [UpdateInstaller] interface, which is
/// what lets iOS slot in later as a single new branch here.
class UpdateInstallerFactory {
  const UpdateInstallerFactory();

  /// Returns the [UpdateInstaller] for the platform this app is
  /// currently running on. Throws [UpdateInstallException] for a
  /// platform that isn't supported yet.
  UpdateInstaller create() {
    if (kIsWeb) {
      throw const UpdateInstallException('CruDoc does not support in-app updates on Web.');
    }
    if (Platform.isWindows) return WindowsUpdateInstaller();
    if (Platform.isAndroid) return AndroidUpdateInstaller();

    // iOS support is fully designed for — see IosUpdateInstaller — but
    // deliberately not wired in here yet: architecture doc §5, "iOS
    // (later, not built now)." When iOS distribution is scoped in, add:
    //   if (Platform.isIOS) return IosUpdateInstaller();
    // That one line is the entire change; nothing else in the update
    // framework needs to move.
    throw UpdateInstallException(
      'CruDoc does not support in-app updates on this platform (${Platform.operatingSystem}) yet.',
    );
  }
}
