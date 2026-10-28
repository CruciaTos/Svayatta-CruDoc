import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:doctor_management_app/core/services/demo_session_service.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// CruDoc IDs ("K7Q9-2XMB"): every account's permanent ID, so people find
// each other without each other's number. One lookup for Teams, Consults
// and Files; the server side is functions/src/crudoc-id.ts.

/// Crockford base32: no I, L, O or U. Same as the server's ALPHABET.
const String _kAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const int _kLength = 8;

/// What someone typed, as the 8 stored characters ("K7Q92XMB"): case,
/// spaces and dashes don't matter, a leading "CD" is dropped, O reads as 0
/// and I or L as 1. Null when it can't be an ID. Mirrors normalizeCrudocId
/// in functions/src/crudoc-id.ts.
String? normalizeCrudocId(String raw) {
  var s = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (s.length == _kLength + 2 && s.startsWith('CD')) s = s.substring(2);
  s = s.replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
  if (s.length != _kLength) return null;
  return s.split('').every(_kAlphabet.contains) ? s : null;
}

/// "K7Q92XMB" (or anything [normalizeCrudocId] reads) -> "K7Q9-2XMB", how
/// the app shows it. Text that isn't an ID comes back unchanged.
String formatCrudocId(String id) {
  final n = normalizeCrudocId(id);
  if (n == null) return id;
  return '${n.substring(0, 4)}-${n.substring(4)}';
}

/// Whether [text] could be a CruDoc ID.
bool looksLikeCrudocId(String text) => normalizeCrudocId(text) != null;

/// A doctor on CruDoc: from a contact match, a directory search or a CruDoc
/// ID. For someone who isn't a doctor only [uid] and [name] are set.
class CruDocDoctor {
  const CruDocDoctor({
    required this.uid,
    required this.name,
    this.specialty = '',
    this.clinicName = '',
    this.city = '',
    this.handle = '',
  });

  final String uid;
  final String name;
  final String specialty;
  final String clinicName;
  final String city;
  final String handle;

  factory CruDocDoctor.fromMap(Map<String, dynamic> m) => CruDocDoctor(
    uid: m['uid'] as String? ?? '',
    name: (m['name'] ?? m['displayName']) as String? ?? '',
    specialty: m['specialty'] as String? ?? '',
    clinicName: m['clinicName'] as String? ?? '',
    city: m['city'] as String? ?? '',
    handle: m['handle'] as String? ?? '',
  );
}

/// Someone on CruDoc, found by their CruDoc ID (or, for a doctor, in the
/// directory). Only doctors can take consults.
class CrudocPerson {
  const CrudocPerson({
    required this.doctor,
    required this.crudocId,
    required this.isDoctor,
  });

  /// Their name (and, for a doctor, specialty, clinic and city).
  final CruDocDoctor doctor;

  /// "K7Q9-2XMB"; empty when they were found another way.
  final String crudocId;
  final bool isDoctor;

  String get uid => doctor.uid;
  String get name => doctor.name;

  factory CrudocPerson.fromMap(Map<String, dynamic> m) => CrudocPerson(
    doctor: CruDocDoctor.fromMap(m),
    crudocId: formatCrudocId(m['crudocId'] as String? ?? ''),
    isDoctor: m['isDoctor'] == true,
  );
}

/// A CruDoc ID lookup the server refused, with a message to show.
class CrudocIdException implements Exception {
  const CrudocIdException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Your own CruDoc ID and finding someone by theirs. Both go through the
/// `referralNetwork` callable (actions myCrudocId and findByCrudocId).
/// Every method throws [CrudocIdException].
class CrudocIdApi {
  CrudocIdApi._();

  /// Works on Windows too, where the Functions plugin doesn't exist.
  static CallableClient client = CallableClient();

  /// The signed-in person's CruDoc ID ("K7Q9-2XMB"), made the first time.
  static Future<String> myId() async {
    final data = await _call('myCrudocId');
    return formatCrudocId(data['crudocId'] as String? ?? '');
  }

  /// The one person whose CruDoc ID is [raw] (typed or pasted, any form
  /// [normalizeCrudocId] reads). Exact match only; rate limited.
  static Future<CrudocPerson> find(String raw) async {
    final id = normalizeCrudocId(raw);
    if (id == null) {
      throw const CrudocIdException(
        'A CruDoc ID is 8 letters and numbers, like K7Q9-2XMB.',
      );
    }
    final data = await _call('findByCrudocId', {'crudocId': id});
    return CrudocPerson.fromMap(data);
  }

  static Future<Map<String, dynamic>> _call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    try {
      final raw = await client.call('referralNetwork', {
        'action': action,
        ...data,
      });
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on CallableException catch (e) {
      debugPrint('[crudocId] $action failed: ${e.code} ${e.message}');
      throw CrudocIdException(switch (e.code) {
        'resource-exhausted' ||
        'failed-precondition' ||
        'invalid-argument' ||
        'permission-denied' ||
        'not-found' =>
          e.message.isEmpty ? "That didn't work. Try again." : e.message,
        'unauthenticated' => 'Sign in again to continue.',
        _ => "Couldn't reach CruDoc. Check the connection and try again.",
      });
    } catch (e) {
      debugPrint('[crudocId] $action failed: $e');
      throw const CrudocIdException(
        "Couldn't reach CruDoc. Check the connection and try again.",
      );
    }
  }
}

/// The signed-in person's CruDoc ID, made the first time it's asked for.
/// Empty in the demo. `ref.invalidate` it to try again after an error.
final myCrudocIdProvider = FutureProvider<String>((ref) async {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null || DemoSessionService.isDemoMode) return '';
  return CrudocIdApi.myId();
});

/// Shows a CruDoc ID as "K7Q9-2XMB" while it is typed or pasted: capitals,
/// no spaces, the dash after four. A leading "CD" is dropped.
class _CrudocIdFormatter extends TextInputFormatter {
  const _CrudocIdFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var s = newValue.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (s.length > _kLength + 2) s = s.substring(0, _kLength + 2);
    if (s.length == _kLength + 2 && s.startsWith('CD')) s = s.substring(2);
    final text = s.length > 4 ? '${s.substring(0, 4)}-${s.substring(4)}' : s;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// A CruDoc ID box. Once the ID is complete it looks the person up (after a
/// short pause) and shows their name with a Doctor or Staff tag, or why no
/// one was found. [onResolved] gets the person, or null whenever the box no
/// longer holds a found ID.
class CrudocIdField extends StatefulWidget {
  const CrudocIdField({
    super.key,
    this.controller,
    this.label = 'CruDoc ID',
    this.onResolved,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String label;
  final ValueChanged<CrudocPerson?>? onResolved;
  final bool autofocus;
  final bool enabled;

  @override
  State<CrudocIdField> createState() => _CrudocIdFieldState();
}

class _CrudocIdFieldState extends State<CrudocIdField> {
  TextEditingController? _own;
  TextEditingController get _controller =>
      widget.controller ?? (_own ??= TextEditingController());

  Timer? _debounce;

  /// The normalized ID last looked up (or being looked up).
  String? _asked;
  bool _looking = false;
  CrudocPerson? _person;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Back in the box with an ID already typed: look it up again.
    final id = normalizeCrudocId(_controller.text);
    if (id != null) {
      _asked = id;
      _looking = true;
      _debounce = Timer(Duration.zero, () => _lookUp(id));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _own?.dispose();
    super.dispose();
  }

  void _changed(String text) {
    final id = normalizeCrudocId(text);
    if (id == _asked) return;
    _debounce?.cancel();
    final hadPerson = _person != null;
    setState(() {
      _asked = id;
      _person = null;
      _error = null;
      _looking = id != null;
    });
    if (hadPerson) widget.onResolved?.call(null);
    if (id == null) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _lookUp(id));
  }

  Future<void> _lookUp(String id) async {
    CrudocPerson? person;
    String? error;
    try {
      person = await CrudocIdApi.find(id);
    } on CrudocIdException catch (e) {
      error = e.message;
    }
    // Typed on while it was looking: that answer is stale.
    if (!mounted || _asked != id) return;
    setState(() {
      _looking = false;
      _person = person;
      _error = error;
    });
    if (person != null) widget.onResolved?.call(person);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final person = _person;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CruTextField(
          label: widget.label,
          controller: _controller,
          hint: 'K7Q9-2XMB',
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          tabular: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [_CrudocIdFormatter()],
          onChanged: _changed,
        ),
        if (_looking) ...[
          const SizedBox(height: CruSpace.s8),
          Text('Looking up…', style: CruType.caption.tint(c.label2)),
        ] else if (_error != null) ...[
          const SizedBox(height: CruSpace.s8),
          Text(_error!, style: CruType.caption.tint(c.label2)),
        ] else if (person != null) ...[
          const SizedBox(height: CruSpace.s8),
          Row(
            children: [
              CruMonogram(name: person.name.isEmpty ? '?' : person.name),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: CruType.callout.w600.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (person.isDoctor)
                      Text(
                        [
                          if (person.doctor.specialty.isNotEmpty)
                            person.doctor.specialty,
                          if (person.doctor.clinicName.isNotEmpty)
                            person.doctor.clinicName,
                          if (person.doctor.city.isNotEmpty) person.doctor.city,
                        ].join(' · '),
                        style: CruType.caption.tint(c.label2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s8),
              CruInfoPill(text: person.isDoctor ? 'Doctor' : 'Staff'),
            ],
          ),
        ],
      ],
    );
  }
}

/// "Your CruDoc ID" with Copy: anyone on CruDoc can find you with it, to
/// send you a referral or invite you to their clinic, even without your
/// number. Hidden when there is no ID (the demo).
class CrudocIdCard extends ConsumerWidget {
  const CrudocIdCard({
    super.key,
    this.description =
        'Share it so anyone on CruDoc can find you, to send you a referral '
        "or invite you to their clinic, even if they don't have your number.",
  });

  final String description;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final id = ref.watch(myCrudocIdProvider);
    final value = id.value ?? '';
    if (!id.isLoading && !id.hasError && value.isEmpty) {
      return const SizedBox.shrink();
    }
    final Widget action;
    if (id.hasError && !id.isLoading) {
      action = CruCapsuleButton(
        label: 'Retry',
        kind: CruCapsuleKind.surface,
        height: CruSize.control,
        onPressed: () => ref.invalidate(myCrudocIdProvider),
      );
    } else if (value.isEmpty) {
      action = const SizedBox.shrink();
    } else {
      action = CruCapsuleButton(
        label: 'Copy',
        kind: CruCapsuleKind.surface,
        height: CruSize.control,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: value));
          _toast(context, 'CruDoc ID copied');
        },
      );
    }
    return CruCard(
      semanticLabel: 'Your CruDoc ID',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Your CruDoc ID', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(description, style: CruType.text.tint(c.label2)),
          const SizedBox(height: CruSpace.s20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      id.isLoading
                          ? 'Loading…'
                          : id.hasError
                          ? "Couldn't load it. Check the connection."
                          : value,
                      style: CruType.callout.tabular.tint(c.label),
                    ),
                    if (value.isNotEmpty && !id.isLoading && !id.hasError) ...[
                      const SizedBox(height: CruSpace.s2),
                      Text(
                        'Only this exact ID finds you.',
                        style: CruType.caption.tint(c.label2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: CruSpace.s16),
              action,
            ],
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  final c = context.cru;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message, style: CruType.text.tint(c.surface)),
      backgroundColor: c.label,
      behavior: SnackBarBehavior.floating,
      shape: cruShape(CruRadius.control),
      margin: const EdgeInsets.all(CruSpace.s16),
      duration: const Duration(seconds: 3),
    ),
  );
}
