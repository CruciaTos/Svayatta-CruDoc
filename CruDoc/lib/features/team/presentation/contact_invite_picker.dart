import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/clinic/clinic_invites.dart';
import 'package:doctor_management_app/core/clinic/clinic_team_api.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Contact matching runs on phones only: desktop and web have no address
/// book to read.
bool get contactMatchingSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// A contact chosen to invite: the name and number go into the form.
class PickedContact {
  const PickedContact({required this.name, required this.phone});
  final String name;

  /// As stored in the address book.
  final String phone;
}

String _consentKey(String uid) => 'contact_matching.consent.$uid';

/// Asks once (per account) before any contact is read: what is checked and
/// that nothing is kept. The yes is saved on the device and, with the time,
/// on the profile. Then picks a contact; null if they stop anywhere.
Future<PickedContact?> pickContactToInvite(
  BuildContext context, {
  required String clinicId,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  if (prefs?.getBool(_consentKey(uid)) != true) {
    if (!context.mounted) return null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Find colleagues in your contacts',
        submitLabel: 'Continue',
        cancelLabel: 'Not now',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: Text(
          "CruDoc checks your contacts' phone numbers to show colleagues "
          "already on the app. Your contacts aren't stored.",
          style: CruType.text.tint(ctx.cru.label2),
        ),
      ),
    );
    if (ok != true) return null;
    await prefs?.setBool(_consentKey(uid), true);
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({
          'contactMatchingConsentAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .catchError((_) {});
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<PickedContact>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ContactInvitePicker(clinicId: clinicId),
    ),
  );
}

class _Entry {
  const _Entry(this.name, this.phone, this.status);
  final String name;
  final String phone;
  final ContactMatchStatus? status;
}

/// The admin's phone contacts: those on CruDoc first ("Your contacts on
/// CruDoc"), then everyone else ("Invite to CruDoc"). Search filters both;
/// pulling down matches again. Pops with the [PickedContact] tapped.
class ContactInvitePicker extends StatefulWidget {
  const ContactInvitePicker({super.key, required this.clinicId});

  final String clinicId;

  @override
  State<ContactInvitePicker> createState() => _ContactInvitePickerState();
}

class _ContactInvitePickerState extends State<ContactInvitePicker> {
  final _search = TextEditingController();

  /// (name, number) for every number in the address book.
  List<(String, String)> _contacts = const [];
  Map<String, ContactMatchStatus> _matches = const {};
  bool _loading = true;
  bool _denied = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      if (mounted) {
        setState(() {
          _denied = true;
          _loading = false;
        });
      }
      return;
    }
    try {
      final all = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      final seen = <String>{};
      final out = <(String, String)>[];
      for (final contact in all) {
        final name = contact.displayName?.trim() ?? '';
        for (final p in contact.phones) {
          final raw = p.number.trim();
          final key = '$name|${invitePhoneE164(raw) ?? raw}';
          if (raw.isEmpty || !seen.add(key)) continue;
          out.add((name.isEmpty ? raw : name, raw));
        }
      }
      out.sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
      if (!mounted) return;
      setState(() => _contacts = out);
      await _match();
    } catch (_) {
      if (mounted) setState(() => _notice = "Couldn't read your contacts.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _match() async {
    if (_contacts.isEmpty) return;
    try {
      final matches = await ClinicTeamApi.instance.matchContacts(
        clinicId: widget.clinicId,
        phones: {for (final c in _contacts) c.$2}.toList(),
      );
      if (mounted) {
        setState(() {
          _matches = matches;
          _notice = null;
        });
      }
    } on ClinicTeamException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final q = _search.text.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final onCruDoc = <_Entry>[];
    final others = <_Entry>[];
    for (final (name, phone) in _contacts) {
      if (q.isNotEmpty &&
          !name.toLowerCase().contains(q) &&
          (qDigits.isEmpty ||
              !phone.replaceAll(RegExp(r'\D'), '').contains(qDigits))) {
        continue;
      }
      final status = _matches[phone];
      (status == null ? others : onCruDoc).add(_Entry(name, phone, status));
    }
    final rows = <Widget>[
      if (onCruDoc.isNotEmpty) ...[
        const _SectionLabel('Your contacts on CruDoc'),
        for (final e in onCruDoc) _ContactRow(entry: e),
      ],
      if (others.isNotEmpty) ...[
        const _SectionLabel('Invite to CruDoc'),
        for (final e in others) _ContactRow(entry: e),
      ],
    ];

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s16,
                CruSpace.s12,
                CruSpace.s8,
                CruSpace.s8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Choose a contact',
                        style: CruType.title.tint(c.label),
                      ),
                    ),
                  ),
                  CruIconButton(
                    icon: CruIcons.close,
                    semanticLabel: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (!_denied)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s16),
                child: CruTextField(
                  label: 'Search',
                  controller: _search,
                  icon: CruIcons.search,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s16,
                  CruSpace.s12,
                  CruSpace.s16,
                  0,
                ),
                child: Text(_notice!, style: CruType.text.tint(c.label2)),
              ),
            const SizedBox(height: CruSpace.s8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _denied
                  ? _Denied(onRetry: () {
                      setState(() {
                        _denied = false;
                        _loading = true;
                      });
                      _load();
                    })
                  : RefreshIndicator(
                      onRefresh: _match,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: CruSpace.s24),
                        children: rows.isEmpty
                            ? [
                                Padding(
                                  padding: const EdgeInsets.all(
                                    CruSpace.s24,
                                  ),
                                  child: Text(
                                    _contacts.isEmpty
                                        ? 'No contacts with phone numbers.'
                                        : 'No contacts match.',
                                    textAlign: TextAlign.center,
                                    style: CruType.text.tint(c.label2),
                                  ),
                                ),
                              ]
                            : rows,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CruSpace.s16,
      CruSpace.s16,
      CruSpace.s16,
      CruSpace.s8,
    ),
    child: Text(text, style: CruType.subhead.tint(context.cru.label2)),
  );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.entry});
  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    void pick() => Navigator.of(
      context,
    ).pop(PickedContact(name: entry.name, phone: entry.phone));
    final Widget trailing = switch (entry.status) {
      ContactMatchStatus.member => Text(
        'Member',
        style: CruType.caption.tint(c.label3),
      ),
      ContactMatchStatus.invited => const WaitingPill('Invited'),
      _ => CruCapsuleButton(label: 'Invite', onPressed: pick),
    };
    final canPick =
        entry.status == null || entry.status == ContactMatchStatus.available;
    return CruPressable(
      onTap: canPick ? pick : null,
      semanticLabel: entry.name,
      builder: (context, hovered) => Container(
        color: hovered ? c.hoverFill : null,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s16,
          vertical: CruSpace.s8,
        ),
        child: Row(
          children: [
            CruMonogram(name: entry.name),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CruType.row.tint(c.label),
                  ),
                  Text(
                    entry.phone,
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CruSpace.s12),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _Denied extends StatelessWidget {
  const _Denied({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.all(CruSpace.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "CruDoc can't see your contacts. Allow access in your phone's "
            'settings, or type the number instead.',
            textAlign: TextAlign.center,
            style: CruType.text.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CruButton(
                label: 'Open settings',
                kind: CruButtonKind.inset,
                onPressed: () => FlutterContacts.permissions.openSettings(),
              ),
              const SizedBox(width: CruSpace.s8),
              CruButton(
                label: 'Try again',
                kind: CruButtonKind.inset,
                onPressed: onRetry,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
