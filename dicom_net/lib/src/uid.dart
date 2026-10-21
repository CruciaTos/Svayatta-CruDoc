import 'dart:math';

/// Well-known DICOM UIDs.
abstract final class DicomUid {
  static const implicitLittle = '1.2.840.10008.1.2';
  static const explicitLittle = '1.2.840.10008.1.2.1';
  static const verification = '1.2.840.10008.1.1';
  static const appContext = '1.2.840.10008.3.1.1.1';

  /// Identifies this implementation in file headers and associations.
  static const implementationClass = '2.25.226104071186733618461240212358371010';
  static const implementationVersion = 'DICOMNET_1';

  static const ctImage = '1.2.840.10008.5.1.4.1.1.2';
  static const dxPresentation = '1.2.840.10008.5.1.4.1.1.1.1';
  static const ioPresentation = '1.2.840.10008.5.1.4.1.1.1.3';
  static const secondaryCapture = '1.2.840.10008.5.1.4.1.1.7';
}

final _rand = Random.secure();

/// A new globally unique UID under the 2.25 (UUID) root.
String newDicomUid() {
  var n = BigInt.zero;
  for (var i = 0; i < 16; i++) {
    n = (n << 8) | BigInt.from(_rand.nextInt(256));
  }
  return '2.25.$n';
}
