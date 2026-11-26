import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
// The camera plugin offers no public way to ask for this mode.
// ignore: implementation_imports
import 'package:camera_android_camerax/src/camerax_library.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraPlatform;
import 'package:flutter/foundation.dart';

/// Android's CONTROL_VIDEO_STABILIZATION_MODE_PREVIEW_STABILIZATION.
const _previewStabilisation = 2;

/// Asks the phone to take the hand shake out of the camera's picture. Does
/// nothing where the phone cannot.
///
/// On Android this is "preview stabilisation" (Android 13 and later), which
/// steadies the preview and the frames the scanner reads alike, so the
/// outline stays on the page. The plain video mode the plugin offers may
/// move one and not the other, so it is not used there.
Future<void> steadyCamera(CameraController camera) async {
  try {
    if (Platform.isIOS) {
      await camera.setVideoStabilizationMode(VideoStabilizationMode.level1);
      return;
    }
    final platform = CameraPlatform.instance;
    if (platform is! AndroidCameraCameraX) return;
    // ignore: invalid_use_of_visible_for_testing_member
    final info = platform.cameraInfo;
    if (info == null) return;
    final modes =
        await Camera2CameraInfo.from(cameraInfo: info).getCameraCharacteristic(
              CameraCharacteristics.controlAvailableVideoStabilizationModes,
            )
            as List<Object?>?;
    if (!(modes?.contains(_previewStabilisation) ?? false)) return;
    await Camera2CameraControl.from(
      cameraControl: platform.cameraControl,
    ).addCaptureRequestOptions(
      CaptureRequestOptions(
        options: <CaptureRequestKey, Object?>{
          CaptureRequest.controlVideoStabilizationMode: _previewStabilisation,
        },
      ),
    );
    debugPrint('[Scanner] preview stabilisation on');
  } catch (e) {
    debugPrint('[Scanner] no stabilisation: $e');
  }
}
