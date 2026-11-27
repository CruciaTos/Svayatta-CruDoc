enum AbhaInputType { abhaNumber, aadhaar, mobile, abhaAddress, invalid }

/// Strips all non-digit characters.
String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// Detects what kind of identifier the user typed into the "Has ABHA" field.
AbhaInputType detectAbhaInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return AbhaInputType.invalid;
  if (RegExp(r'[a-zA-Z@]').hasMatch(trimmed)) {
    return AbhaInputType.abhaAddress;
  }
  final digits = digitsOnly(trimmed);
  switch (digits.length) {
    case 14:
      return AbhaInputType.abhaNumber;
    case 12:
      return AbhaInputType.aadhaar;
    case 10:
      return AbhaInputType.mobile;
    default:
      return AbhaInputType.invalid;
  }
}

/// Formats a 14-digit ABHA number as `NN-NNNN-NNNN-NNNN`.
String formatAbhaNumber(String raw) {
  final d = digitsOnly(raw);
  if (d.length != 14) return raw.trim();
  return '${d.substring(0, 2)}-${d.substring(2, 6)}-'
      '${d.substring(6, 10)}-${d.substring(10, 14)}';
}

bool isValidMobile(String raw) => digitsOnly(raw).length == 10;

bool isValidAadhaar(String raw) => digitsOnly(raw).length == 12;

bool isValidOtp(String raw) => digitsOnly(raw).length == 6;

/// Per-rule validation state for custom ABHA address entry (CRT_ABHA_112).
class AbhaAddressRules {
  const AbhaAddressRules({
    required this.lengthOk,
    required this.charsOk,
    required this.specialCountOk,
    required this.edgesOk,
  });

  final bool lengthOk;
  final bool charsOk;
  final bool specialCountOk;
  final bool edgesOk;

  bool get isValid => lengthOk && charsOk && specialCountOk && edgesOk;

  factory AbhaAddressRules.evaluate(String raw) {
    final s = raw.trim();
    final lengthOk = s.length >= 8 && s.length <= 18;
    final charsOk = s.isNotEmpty && RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(s);
    final dots = '.'.allMatches(s).length;
    final underscores = '_'.allMatches(s).length;
    final specialCountOk = dots <= 1 && underscores <= 1;
    final edgesOk =
        s.isNotEmpty &&
        RegExp(r'^[a-zA-Z0-9]').hasMatch(s) &&
        RegExp(r'[a-zA-Z0-9]$').hasMatch(s);
    return AbhaAddressRules(
      lengthOk: lengthOk,
      charsOk: charsOk,
      specialCountOk: specialCountOk,
      edgesOk: edgesOk,
    );
  }
}
