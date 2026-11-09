import 'package:doctor_management_app/features/radiology/cbct/cbct_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CbctDevice checks screen dimensions and device class', (
    tester,
  ) async {
    bool? canOpen;
    CbctDeviceClass? devClass;

    Future<void> pumpWithSize(double w, double h) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(w, h)),
            child: Builder(
              builder: (context) {
                canOpen = CbctDevice.canOpen3d(context);
                devClass = CbctDevice.deviceClass(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    }

    // 400 x 800 gives false (shortestSide 400 < 600)
    await pumpWithSize(400, 800);
    expect(canOpen, isFalse);

    // 800 x 1200 gives true (shortestSide 800 >= 600)
    await pumpWithSize(800, 1200);
    expect(canOpen, isTrue);

    // 1280 x 800 gives true (shortestSide 800 >= 600)
    await pumpWithSize(1280, 800);
    expect(canOpen, isTrue);

    // Windows device class is pc
    expect(devClass, CbctDeviceClass.pc);
  });
}
