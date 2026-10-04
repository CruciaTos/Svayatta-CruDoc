import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class J2kImage {
  const J2kImage(this.width, this.height, this.precision, this.signed, this.pixels);
  final int width, height, precision;
  final bool signed;
  final Int32List pixels;
}

class J2kDecodeException implements Exception {
  final int code;
  final String message;

  J2kDecodeException(this.code, [String? message])
      : message = message ?? _defaultMessage(code);

  static String _defaultMessage(int code) {
    switch (code) {
      case 1:
        return 'Failed to create OpenJPEG stream';
      case 2:
        return 'Failed to setup OpenJPEG decoder';
      case 3:
        return 'Failed to read codestream header';
      case 4:
        return 'Failed to decode codestream';
      case 5:
        return 'Codestream contains no components';
      case 6:
        return 'Failed to allocate memory for decoded pixels';
      default:
        return 'Decode failed with error code $code';
    }
  }

  @override
  String toString() => 'J2kDecodeException($code): $message';
}

/// True where the native library is built (Android, Windows).
bool get j2kSupported {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isWindows;
}

typedef _CrudocJ2kDecodeC = Int32 Function(
  Pointer<Uint8> data,
  Int64 len,
  Int32 reduce,
  Pointer<Pointer<Int32>> outPixels,
  Pointer<Int32> outW,
  Pointer<Int32> outH,
  Pointer<Int32> outPrec,
  Pointer<Int32> outSigned,
);

typedef _CrudocJ2kDecodeDart = int Function(
  Pointer<Uint8> data,
  int len,
  int reduce,
  Pointer<Pointer<Int32>> outPixels,
  Pointer<Int32> outW,
  Pointer<Int32> outH,
  Pointer<Int32> outPrec,
  Pointer<Int32> outSigned,
);

typedef _CrudocJ2kFreeC = Void Function(Pointer<Int32> p);
typedef _CrudocJ2kFreeDart = void Function(Pointer<Int32> p);

final DynamicLibrary _dylib = () {
  final env = Platform.environment['CRUDOC_J2K_LIB'];
  if (env != null && env.isNotEmpty) {
    return DynamicLibrary.open(env);
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('crudoc_j2k.dll');
  }
  return DynamicLibrary.open('libcrudoc_j2k.so');
}();

final _CrudocJ2kDecodeDart _crudocJ2kDecode =
    _dylib.lookupFunction<_CrudocJ2kDecodeC, _CrudocJ2kDecodeDart>('crudoc_j2k_decode');

final _CrudocJ2kFreeDart _crudocJ2kFree =
    _dylib.lookupFunction<_CrudocJ2kFreeC, _CrudocJ2kFreeDart>('crudoc_j2k_free');

/// Decodes [bytes]; [reduce] 0 = full, 1 = half. Call inside an isolate.
J2kImage decodeJ2k(Uint8List bytes, {int reduce = 0}) {
  final Pointer<Uint8> nativeBytes = malloc<Uint8>(bytes.length);
  final Pointer<Pointer<Int32>> outPixelsPtr = malloc<Pointer<Int32>>();
  final Pointer<Int32> outWPtr = malloc<Int32>();
  final Pointer<Int32> outHPtr = malloc<Int32>();
  final Pointer<Int32> outPrecPtr = malloc<Int32>();
  final Pointer<Int32> outSignedPtr = malloc<Int32>();

  outPixelsPtr.value = nullptr;

  try {
    nativeBytes.asTypedList(bytes.length).setAll(0, bytes);

    final int rc = _crudocJ2kDecode(
      nativeBytes,
      bytes.length,
      reduce,
      outPixelsPtr,
      outWPtr,
      outHPtr,
      outPrecPtr,
      outSignedPtr,
    );

    if (rc != 0) {
      throw J2kDecodeException(rc);
    }

    final Pointer<Int32> pixelsPtr = outPixelsPtr.value;
    if (pixelsPtr == nullptr) {
      throw J2kDecodeException(-1, 'Null pixel pointer returned');
    }

    try {
      final int width = outWPtr.value;
      final int height = outHPtr.value;
      final int precision = outPrecPtr.value;
      final bool signed = outSignedPtr.value != 0;
      final int count = width * height;

      final Int32List pixels = Int32List.fromList(pixelsPtr.asTypedList(count));

      return J2kImage(width, height, precision, signed, pixels);
    } finally {
      _crudocJ2kFree(pixelsPtr);
    }
  } finally {
    malloc.free(nativeBytes);
    malloc.free(outPixelsPtr);
    malloc.free(outWPtr);
    malloc.free(outHPtr);
    malloc.free(outPrecPtr);
    malloc.free(outSignedPtr);
  }
}
