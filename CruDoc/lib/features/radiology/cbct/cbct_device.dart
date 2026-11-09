import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The kind of device the 3D viewer is on; the page tunes its loading.
enum CbctDeviceClass { pc, tablet }

/// Where the 3D viewer can run: Windows, macOS, iPad and Android tablets
/// (a phone screen is too small for four panels).
abstract final class CbctDevice {
  static bool get platformSupported =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

  /// True when the 3D actions should be offered on this screen.
  static bool canOpen3d(BuildContext context) =>
      platformSupported && MediaQuery.sizeOf(context).shortestSide >= 600;

  static CbctDeviceClass deviceClass(BuildContext context) =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
      ? CbctDeviceClass.pc
      : CbctDeviceClass.tablet;
}
