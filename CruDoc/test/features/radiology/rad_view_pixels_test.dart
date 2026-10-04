import 'dart:typed_data';

import 'package:doctor_management_app/features/radiology/imaging/rad_view_pixels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bilinear upscale 2x2 to 4x4 keeps corner values and stays within min/max', () {
    final src = Float32List.fromList([
      10.0, 20.0,
      30.0, 40.0,
    ]);

    const srcW = 2;
    const srcH = 2;
    const dstW = 4;
    const dstH = 4;

    final dst = bilinearUpscale(src, srcW, srcH, dstW, dstH);

    expect(dst.length, dstW * dstH);

    // Corner checks:
    // top-left (0, 0)
    expect(dst[0 * dstW + 0], 10.0);
    // top-right (3, 0)
    expect(dst[0 * dstW + 3], 20.0);
    // bottom-left (0, 3)
    expect(dst[3 * dstW + 0], 30.0);
    // bottom-right (3, 3)
    expect(dst[3 * dstW + 3], 40.0);

    // Stays within min and max
    for (int i = 0; i < dst.length; i++) {
      expect(dst[i], greaterThanOrEqualTo(10.0));
      expect(dst[i], lessThanOrEqualTo(40.0));
    }
  });
}
