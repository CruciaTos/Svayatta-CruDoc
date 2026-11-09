import 'package:doctor_management_app/features/radiology/cbct/cbct_fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wide viewport is limited by height', () {
    final f = CbctFit.of(width: 400, height: 300, u: 40, v: 40);
    expect(f.parallelScale, closeTo(20, 1e-9));
    expect(f.pxPerMm, closeTo(7.5, 1e-9));
    expect(f.rect.width, closeTo(300, 1e-9));
    expect(f.rect.center.dx, closeTo(200, 1e-9));
    expect(f.rect.center.dy, closeTo(150, 1e-9));
  });

  test('tall viewport is limited by width', () {
    final f = CbctFit.of(width: 300, height: 400, u: 40, v: 40);
    expect(f.parallelScale, closeTo(26.6667, 1e-3));
    expect(f.pxPerMm, closeTo(7.5, 1e-9));
    expect(f.rect.height, closeTo(300, 1e-9));
  });

  test('a wide plane in a square viewport', () {
    final f = CbctFit.of(width: 500, height: 500, u: 40, v: 20);
    expect(f.parallelScale, closeTo(20, 1e-9));
    expect(f.pxPerMm, closeTo(12.5, 1e-9));
    expect(f.rect.width, closeTo(500, 1e-9));
    expect(f.rect.height, closeTo(250, 1e-9));
  });
}
