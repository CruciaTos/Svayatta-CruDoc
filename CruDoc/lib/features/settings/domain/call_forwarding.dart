/// Forwarding the doctor's own number to the clinic's AI receptionist.
///
/// Uses the standard GSM codes, which the phone sends to the network when
/// the doctor presses call:
///   every call   `**21*+91{AI number}#`    off: `##21#`
///   missed calls `**004*+91{AI number}#`   off: `##004#`
/// "Missed calls" is the operator's bundle of busy, no answer and
/// unreachable, so the phone still rings first.
library;

enum ForwardMode {
  all('Every call'),
  missed('Missed calls');

  const ForwardMode(this.label);
  final String label;
}

/// Only Jio matters: it blocks the code for forwarding every call, so its
/// customers have to use the phone's call settings for that one.
enum PhoneNetwork {
  jio('Jio'),
  other('Airtel, Vi, BSNL');

  const PhoneNetwork(this.label);
  final String label;
}

enum ForwardPlatform { android, ios, other }

/// How the doctor turns forwarding on or off on this phone.
enum ForwardMethod {
  /// Android: open the dialler with the code filled in; they press call.
  dial,

  /// iPhone (iOS refuses dialler links containing * or #) and computers:
  /// show the code with a copy button.
  copyCode,

  /// Jio, every call: step-by-step through the phone's call settings.
  phoneSettings,
}

ForwardMethod forwardMethod({
  required ForwardPlatform platform,
  required PhoneNetwork network,
  required ForwardMode mode,
}) {
  if (network == PhoneNetwork.jio && mode == ForwardMode.all) {
    return ForwardMethod.phoneSettings;
  }
  return platform == ForwardPlatform.android
      ? ForwardMethod.dial
      : ForwardMethod.copyCode;
}

/// The code that turns [mode] on, forwarding to [aiNumber] (any Indian
/// number format). Null when [aiNumber] is not an Indian number.
String? forwardOnCode(ForwardMode mode, String aiNumber) {
  final digits = indianNumberDigits(aiNumber);
  if (digits == null) return null;
  return switch (mode) {
    ForwardMode.all => '**21*+$digits#',
    ForwardMode.missed => '**004*+$digits#',
  };
}

/// The code that turns [mode] off.
String forwardOffCode(ForwardMode mode) => switch (mode) {
  ForwardMode.all => '##21#',
  ForwardMode.missed => '##004#',
};

/// Any Indian number as 12 digits starting 91, or null. Mirrors
/// `indianNumberDigits` in functions/src/voice/context.ts, which keys
/// `voice_lines` by this form.
String? indianNumberDigits(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
  if (digits.length == 10) digits = '91$digits';
  return digits.length == 12 && digits.startsWith('91') ? digits : null;
}

/// "918064261740" → "+91 80642 61740". Anything else comes back unchanged.
String formatIndianNumber(String raw) {
  final d = indianNumberDigits(raw);
  if (d == null) return raw;
  return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
}

/// "+918064261740", for typing into a phone's settings.
String dialableIndianNumber(String raw) {
  final d = indianNumberDigits(raw);
  return d == null ? raw : '+$d';
}

/// Jio's mobile network codes in India (MCC 405, MNC 840 and 854–874).
final _jioMccMnc = {
  '405840',
  for (var mnc = 854; mnc <= 874; mnc++) '405$mnc',
};

/// Whether a SIM is Jio, from its operator name or network code.
bool isJioSim({String? name, String? mccMnc}) {
  if (name != null && name.toLowerCase().contains('jio')) return true;
  return mccMnc != null && _jioMccMnc.contains(mccMnc.trim());
}
