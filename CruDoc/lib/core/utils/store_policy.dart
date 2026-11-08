import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Apple's rules: no buying features inside the app on iPhone, iPad or Mac.
bool get storePurchasesAllowed =>
    kIsWeb || !(Platform.isIOS || Platform.isMacOS);

/// Bill and document scanning: phones use the camera and ML Kit; Windows uses
/// the desktop reader (Sarvam / PaddleOCR). Neither plugin exists on Mac, so
/// the Scan buttons are hidden there.
bool get documentScanSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows);

