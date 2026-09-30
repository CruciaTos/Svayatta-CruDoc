import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_render.dart';

/// Longest edge of a cloud preview, in pixels. Big enough for the
/// thumbnail strip and study cards, small enough to stay a few tens of KB.
const int radPreviewMaxEdge = 512;

/// A JPEG preview of an image file at its default window, or null when the
/// file can't be decoded (compressed DICOM, no pixel data).
///
/// Runs in an isolate: decoding a large DICOM takes a while.
Future<Uint8List?> radPreviewJpeg(Uint8List bytes, RadFileKind kind) =>
    Isolate.run(() => renderRadPreviewJpeg(bytes, kind));

/// The work behind [radPreviewJpeg], synchronous for tests.
Uint8List? renderRadPreviewJpeg(Uint8List bytes, RadFileKind kind) {
  final RadPixels px;
  try {
    px = decodeRadPixels(bytes, kind);
  } catch (_) {
    return null;
  }
  final longest = math.max(px.width, px.height);
  final step = math.max(1, (longest / radPreviewMaxEdge).ceil());
  final (center, width) = px.defaultWindow;
  final rgba = renderDisplay(
    px,
    px.values,
    RadDisplay(center: center, width: width, invert: px.invert),
    step: step,
  );
  final image = img.Image.fromBytes(
    width: rgba.width,
    height: rgba.height,
    bytes: rgba.bytes.buffer,
    bytesOffset: rgba.bytes.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 80);
}
