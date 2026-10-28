# Antigravity brief: drag a file onto a colleague to send it

Paste this whole file into Antigravity. It is a standalone brief.

## ▶ DO NOW

Do Tasks 1 to 9 in order, then run the Checks once at the end. Then **GATE: stop and report.** Do not deploy, commit or push.

## What we're building

On the Files screen (desktop and tablet, not phones), a row of colleagues sits right under the **New folder / Add files** buttons:

```
                                         [ New folder ]  [ + Add files ]
          Drag a file onto a colleague to send   (AM)   (RK)   (SP)   (DN)
                                                 Anita  Rohan  Sneha  Dev
[ Search …            ]  [ Patient All ]  [≡ ⊞]  [ Sort Newest first ]
```

- **Drop a file on a colleague**: the file is sent to them at once. It goes direct on clinic Wi-Fi when one of their devices answers, otherwise through the cloud (this already exists, see Background). A snackbar says where it went and offers **Undo** (cancels the offer).
- **Drag, hold over a colleague for 1 second**: their avatar **lifts** (grows, rises a little, gets a shadow) and the caption says "Swipe right for a note".
- **While lifted, keep dragging to the right (48 px)**: a **compose popup** opens, like writing an email. It shows: To (that colleague, fixed), For (the file's patient), Subject, Note, the attached file(s), and **Add from this PC…** for more files. **Send** sends everything with the subject and note.
- Releasing on a lifted avatar without swiping still just sends.
- Colleagues who can't take the dragged file (no clinical access, or not assigned to that patient) dim and refuse the drop, and their caption shows why.
- The colleague who receives sees the subject and note on the Incoming card and in Transfers.

### Assumed decisions (Soham can change these)

- D1: Desktop and tablet only. Phones keep the ⋯ menu → Send to colleague.
- D2: A plain drop sends immediately, with Undo in the snackbar.
- D3: Hold time 1 second; swipe distance 48 px to the right.
- D4: Everything in one compose is for **one patient** (the dragged file's). Files added from this PC are also saved to that patient's Files, which is how they get a fingerprint and are uploaded once.
- D5: Subject at most 120 characters, note at most 2000, both encrypted like file names.
- D6: Strip order: the colleagues you sent to most recently first, then everyone else by name. All active colleagues are shown; the row scrolls sideways if it's long.

## Rules (how to work)

- Work without pausing. Write every task first, then run all Checks once at the end. Run slow commands (analyze, tests, app run) in the background and carry on.
- A step that says **STOP** means: skip that part, write down what you saw, and carry on. Only the GATE line stops the run.
- If a step doesn't match the code you see (a name or line is different), skip that step, write down what you saw, and carry on.
- Change only the files named in each task. Do not rename, move or reformat anything else. Do not delete any file.
- Do **not** touch `firestore.rules`, `storage.rules`, `functions/`, or anything under `lib/features/files/lan/` except where a task says so. Claude does rules and server work after the GATE.
- Do not commit, push, or run `firebase deploy`.
- Paths are relative to the `CruDoc/` folder.
- UI rules (must follow):
  - Colours only from `context.cru` (`c.label`, `c.label2`, `c.inset`, `c.surface`, `c.hairline`, `c.accent`, `c.accentText`, `c.accentWash`). No `Colors.*`, no `Color(0x…)`.
  - Text only from `CruType.*` with `.tint(color)`, `.w500`, `.w600`. No `fontSize:`.
  - Spacing only `CruSpace.s4 / s8 / s12 / s16 / s20 / s24 / s32`. Radii from `CruRadius`.
  - Motion: `CruMotion.of(context, CruMotion.fast)` with `CruMotion.curve` (200 ms, easeOutCubic, no bounce).
  - Avatars are grey monograms (`c.inset` circle, `c.label2` initials), never coloured.
  - Blue (`c.accent`) only for the ring of the colleague a file is over. Never red.

## Background (what already exists — use it, don't rebuild it)

- File rows and grid tiles are already draggable as `Draggable<FileEntry>` (`lib/features/files/presentation/widgets/files_list.dart`, class `_DraggableFile`), today only for moving into folders. `FileEntry` has `.file` (a `PatientFile`) and `.canManage`.
- Folders accept drops with `DragTarget<FileEntry>` (`FileDropTarget` in `lib/features/files/presentation/widgets/files_bars.dart`). Copy its ring style.
- Sending: `lib/features/files/presentation/send_sheet.dart` (`_SendSheetState._sendTo`) finds a colleague's device, tries Wi-Fi, makes the offers with `FileOffersRepository.instance.createOffers(...)`, and sends them over Wi-Fi. Task 3 moves this into a shared helper.
- Offers: `lib/features/files/data/file_offer_model.dart` (`FileOffer`) and `lib/features/files/data/file_offers_repository.dart` (`createOffers`, `cancelOffer`).
- Colleagues: `clinicMembersProvider` (`lib/features/team/data/team_providers.dart`) gives `List<ClinicMember>` with `uid`, `name`, `kind` (`MemberKind.doctor` / `staff`), `perms` (a set of `ClinicPermission`), `active`.
- Sent offers: `sentOffersProvider` and `hasColleaguesProvider` in `lib/features/files/presentation/transfers_sheet.dart`.
- Patients: `patientsStreamProvider` (`lib/features/patients/data/providers/patient_providers.dart`), `Patient.fullName`, `Patient.assignedDoctorUids`.
- Adding files from disk: `FileSource` and `FilesRepository.instance.addFilesWithIds(sources, patientId: ...)` (`lib/features/files/data/files_repository.dart`) copy them in, fingerprint them and queue the upload; `FilesRepository.instance.file(id)` returns the new `PatientFile`.
- Dialog shell: `CruFormDialog` (title, subtitle, leading, body, submitLabel, onSubmit, busy, dirty, footerHint).

---

## Task 1: Subject and note on an offer (model)

File: `lib/features/files/data/file_offer_model.dart`, class `FileOffer`.

1. Add two optional constructor parameters next to `this.fromDoctorName = '',`:
   ```dart
   this.subject = '',
   this.note = '',
   ```
2. Add the fields (below `fromDoctorName`):
   ```dart
   /// Optional, written in the compose popup. Encrypted in Firestore.
   final String subject;
   final String note;
   ```
3. In `copyWith(...)`, pass them through unchanged: add `subject: subject, note: note,` to the `FileOffer(` it returns.
4. In `toFirestore()`, add after the `'thumb'` line:
   ```dart
   if (subject.isNotEmpty) 'subject': FieldCipher.encrypt(subject),
   if (note.isNotEmpty) 'note': FieldCipher.encrypt(note),
   ```
   (`toJson()` spreads `toFirestore()`, so Wi-Fi offers carry them too.)
5. In `factory FileOffer.fromFirestore(...)`, add to the returned `FileOffer(`:
   ```dart
   subject: FieldCipher.decrypt(data['subject'] as String? ?? ''),
   note: FieldCipher.decrypt(data['note'] as String? ?? ''),
   ```

Check: `flutter analyze lib/features/files/data/file_offer_model.dart` is clean.

## Task 2: `createOffers` takes a subject and note

File: `lib/features/files/data/file_offers_repository.dart`, method `createOffers`.

1. Add two named parameters after `FileOfferVia via = FileOfferVia.cloud,`:
   ```dart
   String subject = '',
   String note = '',
   ```
2. In the `FileOffer(` it builds for each file, add `subject: subject, note: note,`.

Check: analyze clean.

## Task 3: One shared send helper (new file)

Create `lib/features/files/data/colleague_send.dart` with exactly this content:

```dart
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/file_offers_repository.dart';
import 'package:doctor_management_app/features/files/lan/device_registry_service.dart';
import 'package:doctor_management_app/features/files/lan/lan_client.dart';
import 'package:doctor_management_app/features/files/lan/lan_server.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Why [m] can't receive files for [patient], or null when they can.
String? colleagueBlockReason(ClinicMember m, {Patient? patient}) {
  if (!m.active) return 'Not in the clinic';
  if (!m.perms.contains(ClinicPermission.clinicalView)) {
    return "Can't receive patient files";
  }
  if (!m.perms.contains(ClinicPermission.clinicalEdit)) {
    return "Can't save files";
  }
  final scoped =
      ClinicSession.instance.access?.clinicalAccessScope == 'assigned';
  if (scoped && m.kind == MemberKind.doctor) {
    final assigned = patient?.assignedDoctorUids ?? const [];
    if (assigned.isNotEmpty && !assigned.contains(m.uid)) {
      return 'Not assigned to this patient';
    }
  }
  return null;
}

/// Sends [files] to [colleague]: direct on clinic Wi-Fi when one of their
/// devices answers, otherwise through the cloud. Returns the offers made
/// (Undo cancels them).
Future<List<FileOffer>> sendFilesToColleague({
  required String clinicId,
  required ClinicMember colleague,
  required List<PatientFile> files,
  String subject = '',
  String note = '',
}) async {
  var via = FileOfferVia.cloud;
  final peer = await DeviceRegistryService.instance.findColleagueDevice(
    clinicId: clinicId,
    colleagueUid: colleague.uid,
  );
  ({String ip, int port, String nonce, String deviceId})? probe;
  String? token;
  if (peer != null) {
    probe = await LanClient.instance.probePeer(peer);
    if (probe != null) {
      token = await LanClient.instance.createSession(
        peerIp: probe.ip,
        peerPort: probe.port,
        peerCertSha256: peer.certSha256,
        peerDeviceId: probe.deviceId,
        nonce: probe.nonce,
      );
      if (token != null) via = FileOfferVia.lan;
    }
  }

  final offers = await FileOffersRepository.instance.createOffers(
    clinicId: clinicId,
    recipientUid: colleague.uid,
    files: files,
    via: via,
    subject: subject,
    note: note,
  );

  if (via == FileOfferVia.lan) {
    for (final offer in offers) {
      LanServer.instance.registerOpenOffer(offer);
      await LanClient.instance.sendOfferOverLan(
        peerIp: probe!.ip,
        peerPort: probe.port,
        peerCertSha256: peer!.certSha256,
        sessionToken: token!,
        offer: offer,
      );
    }
  }
  return offers;
}

/// Cancels [offers] (the snackbar's Undo). Errors are ignored: an offer
/// already accepted can't be cancelled.
Future<void> undoSend(List<FileOffer> offers) async {
  for (final o in offers) {
    try {
      await FileOffersRepository.instance.cancelOffer(o);
      LanServer.instance.unregisterOpenOffer(o.id);
    } catch (_) {}
  }
}
```

If `probePeer` returns a different record shape than `({String ip, int port, String nonce, String deviceId})?`, copy the shape used in `send_sheet.dart` instead.

Check: analyze clean.

## Task 4: The send sheet uses the helper

File: `lib/features/files/presentation/send_sheet.dart`.

1. Add `import 'package:doctor_management_app/features/files/data/colleague_send.dart';`.
2. Replace the whole body of `_ineligibleReason(ClinicMember m)` with:
   ```dart
   return colleagueBlockReason(m, patient: widget.patient);
   ```
3. In `_sendTo`, replace everything from `FileOfferVia via = FileOfferVia.cloud;` down to (and including) the closing `}` of the `if (via == FileOfferVia.lan && ...)` block with:
   ```dart
   final offers = await sendFilesToColleague(
     clinicId: widget.clinicId,
     colleague: colleague,
     files: widget.files,
   );
   final via = offers.isNotEmpty ? offers.first.via : FileOfferVia.cloud;
   ```
   Keep the snackbar code after it (it uses `via`).
4. Remove imports the file no longer uses (analyze will list them).

Check: analyze clean; the ⋯ menu → Send to colleague still works the same.

## Task 5: Every visible file can be dragged; folders still only take your own

1. File `lib/features/files/presentation/widgets/files_list.dart`, class `_DraggableFile`, method `build`. Replace the first line:
   ```dart
   if (!entry.canManage) return child;
   ```
   with nothing, and after the line that defines `touch` add:
   ```dart
   // Phones don't have the colleague row: there, only files you may move
   // into folders are draggable, as before.
   if (touch && !entry.canManage) return child;
   ```
   Keep the rest of the method as it is.
2. File `lib/features/files/presentation/widgets/files_bars.dart`, class `FileDropTarget`. Change
   ```dart
   onWillAcceptWithDetails: (d) => d.data.file.folderId != folderId,
   ```
   to
   ```dart
   onWillAcceptWithDetails: (d) =>
       d.data.canManage && d.data.file.folderId != folderId,
   ```

Check: on Windows, a file you didn't add can be dragged but a folder won't take it; your own files still move into folders.

## Task 6: Monogram avatar (new small file)

Create `lib/features/files/presentation/widgets/colleague_monogram.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Up to two initials, ignoring a leading "Dr" / "Dr.".
String colleagueInitials(String name) {
  final words = [
    for (final w in name.trim().split(RegExp(r'\s+')))
      if (w.isNotEmpty && w.toLowerCase() != 'dr' && w.toLowerCase() != 'dr.') w,
  ];
  if (words.isEmpty) return '?';
  final first = words.first[0];
  final last = words.length > 1 ? words.last[0] : '';
  return (first + last).toUpperCase();
}

/// The first word of the name after "Dr", for the caption under an avatar.
String colleagueShortName(String name) {
  final words = [
    for (final w in name.trim().split(RegExp(r'\s+')))
      if (w.isNotEmpty && w.toLowerCase() != 'dr' && w.toLowerCase() != 'dr.') w,
  ];
  return words.isEmpty ? 'Colleague' : words.first;
}

/// Grey monogram circle.
class ColleagueMonogram extends StatelessWidget {
  const ColleagueMonogram({super.key, required this.name, this.size = CruSize.actionButton});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.inset,
        shape: CircleBorder(side: BorderSide(color: c.hairline)),
      ),
      child: Text(
        colleagueInitials(name),
        style: CruType.callout.w600.tint(c.label2),
      ),
    );
  }
}
```

Check: analyze clean.

## Task 7: The colleague row (new file)

Create `lib/features/files/presentation/widgets/colleague_strip.dart`. It has three parts. Write them as given; the hold-and-swipe logic is exact, keep it as is.

### 7a. Who is in the row

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/features/files/data/colleague_send.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/compose_transfer_dialog.dart';
import 'package:doctor_management_app/features/files/presentation/transfers_sheet.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/colleague_monogram.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Active colleagues: the ones you sent to most recently first, then the
/// rest by name.
final stripColleaguesProvider = Provider.autoDispose<List<ClinicMember>>((ref) {
  final me = FilesRepository.instance.uid;
  final members = ref.watch(clinicMembersProvider).value ?? const [];
  final sent = ref.watch(sentOffersProvider).value ?? const [];
  final lastSent = <String, DateTime>{};
  for (final o in sent) {
    final t = lastSent[o.to];
    if (t == null || o.createdAt.isAfter(t)) lastSent[o.to] = o.createdAt;
  }
  final list = [
    for (final m in members)
      if (m.active && m.uid != me) m,
  ];
  list.sort((a, b) {
    final ta = lastSent[a.uid];
    final tb = lastSent[b.uid];
    if (ta != null && tb != null) return tb.compareTo(ta);
    if (ta != null) return -1;
    if (tb != null) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
});
```

### 7b. The row

```dart
/// "Drag a file onto a colleague to send" and one drop target per
/// colleague, right-aligned under the header buttons.
class ColleagueStrip extends ConsumerWidget {
  const ColleagueStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final colleagues = ref.watch(stripColleaguesProvider);
    if (colleagues.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // A lifted avatar grows past the row; don't cut it off.
        clipBehavior: Clip.none,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Drag a file onto a colleague to send',
                style: CruType.caption.tint(c.label2),
              ),
              const SizedBox(width: CruSpace.s12),
              for (final m in colleagues) ...[
                ColleagueDropChip(member: m),
                const SizedBox(width: CruSpace.s4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

### 7c. One colleague: drop, hold to lift, swipe right to compose

```dart
class ColleagueDropChip extends ConsumerStatefulWidget {
  const ColleagueDropChip({super.key, required this.member});

  final ClinicMember member;

  @override
  ConsumerState<ColleagueDropChip> createState() => _ColleagueDropChipState();
}

class _ColleagueDropChipState extends ConsumerState<ColleagueDropChip> {
  static const _holdToLift = Duration(seconds: 1);
  static const _swipeToCompose = 48.0;

  Timer? _holdTimer;
  bool _hovering = false;
  bool _lifted = false;
  bool _sending = false;

  /// Set once the compose popup opened for this drag: the drop that ends
  /// the drag must not also send.
  bool _composeOpened = false;

  /// Why the file being dragged can't go to this colleague.
  String? _blocked;

  /// Left edge of the dragged file, now and when the avatar lifted.
  double _lastX = 0;
  double _liftX = 0;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _reset() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!mounted) return;
    setState(() {
      _hovering = false;
      _lifted = false;
      _blocked = null;
    });
  }

  bool _onWillAccept(DragTargetDetails<FileEntry> d) {
    final patients = ref.read(patientsStreamProvider).value ?? const [];
    final patient = patients
        .where((p) => p.id == d.data.file.patientId)
        .firstOrNull;
    final reason = colleagueBlockReason(widget.member, patient: patient);
    if (reason != null) {
      setState(() => _blocked = reason);
      return false;
    }
    _composeOpened = false;
    _lastX = d.offset.dx;
    setState(() => _hovering = true);
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdToLift, () {
      if (!mounted || !_hovering) return;
      setState(() {
        _lifted = true;
        _liftX = _lastX;
      });
    });
    return true;
  }

  void _onMove(DragTargetDetails<FileEntry> d) {
    _lastX = d.offset.dx;
    if (_lifted && !_composeOpened && _lastX - _liftX >= _swipeToCompose) {
      _composeOpened = true;
      final file = d.data.file;
      _reset();
      // Next frame: the drag is still running while the popup opens.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showComposeTransferDialog(
          context,
          to: widget.member,
          files: [file],
        );
      });
    }
  }

  Future<void> _onAccept(DragTargetDetails<FileEntry> d) async {
    final opened = _composeOpened;
    _reset();
    if (opened) return;
    await _sendNow([d.data.file]);
  }

  Future<void> _sendNow(List<PatientFile> files) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = widget.member.name;
    setState(() => _sending = true);
    try {
      final offers = await sendFilesToColleague(
        clinicId: FilesRepository.instance.doctorId,
        colleague: widget.member,
        files: files,
      );
      final wifi = offers.isNotEmpty && offers.first.via == FileOfferVia.lan;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Sent “${files.first.name}” to $name '
            '${wifi ? 'on clinic Wi-Fi' : 'through the cloud'}',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'Undo', onPressed: () => undoSend(offers)),
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Couldn't send to $name: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final m = widget.member;
    final motion = CruMotion.of(context, CruMotion.fast);
    final caption =
        _blocked ??
        (_lifted
            ? 'Swipe right for a note'
            : _hovering
            ? 'Drop to send'
            : colleagueShortName(m.name));
    return DragTarget<FileEntry>(
      onWillAcceptWithDetails: _onWillAccept,
      onMove: _onMove,
      onLeave: (_) => _reset(),
      onAcceptWithDetails: _onAccept,
      builder: (context, _, _) => Tooltip(
        message: m.name,
        child: AnimatedOpacity(
          opacity: _blocked != null ? 0.4 : 1,
          duration: motion,
          curve: CruMotion.curve,
          child: SizedBox(
            width: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSlide(
                  offset: Offset(0, _lifted ? -0.12 : 0),
                  duration: motion,
                  curve: CruMotion.curve,
                  child: AnimatedScale(
                    scale: _lifted ? 1.15 : (_hovering ? 1.05 : 1),
                    duration: motion,
                    curve: CruMotion.curve,
                    child: AnimatedContainer(
                      duration: motion,
                      curve: CruMotion.curve,
                      decoration: ShapeDecoration(
                        shape: CircleBorder(
                          side: BorderSide(
                            color: _hovering
                                ? c.accent
                                : c.accent.withValues(alpha: 0),
                            width: 2,
                          ),
                        ),
                        shadows: [
                          BoxShadow(
                            color: c.label.withValues(alpha: _lifted ? 0.18 : 0),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _sending
                          ? SizedBox.square(
                              dimension: CruSize.actionButton,
                              child: Padding(
                                padding: const EdgeInsets.all(CruSpace.s12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.label2,
                                ),
                              ),
                            )
                          : ColleagueMonogram(name: m.name),
                    ),
                  ),
                ),
                const SizedBox(height: CruSpace.s4),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: CruType.caption.tint(
                    _hovering ? c.accentText : c.label2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

If `onMove` is not called while a drag hovers on this Flutter version, write it down and STOP this part (the hold-to-lift still works; Claude will finish the swipe).

Check: analyze clean.

## Task 8: Compose popup (new file)

Create `lib/features/files/presentation/compose_transfer_dialog.dart`. Write this:

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/features/files/data/colleague_send.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_offer_model.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/colleague_monogram.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// "Send to <colleague>": subject, note and files, like writing an email.
/// Every file is for the patient of the first one.
Future<void> showComposeTransferDialog(
  BuildContext context, {
  required ClinicMember to,
  required List<PatientFile> files,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ComposeDialog(to: to, files: files),
);

class _ComposeDialog extends ConsumerStatefulWidget {
  const _ComposeDialog({required this.to, required this.files});

  final ClinicMember to;
  final List<PatientFile> files;

  @override
  ConsumerState<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends ConsumerState<_ComposeDialog> {
  final _subject = TextEditingController();
  final _note = TextEditingController();
  late final List<PatientFile> _files = [...widget.files];
  bool _busy = false;
  bool _adding = false;

  String get _patientId => widget.files.first.patientId;

  @override
  void dispose() {
    _subject.dispose();
    _note.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  Future<void> _addFromPc() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _adding = true);
    try {
      final sources = [
        for (final f in result.files)
          if (f.path != null)
            FileSource(name: f.name, sizeBytes: f.size, path: f.path),
      ];
      final skipped = sources.where((s) => s.problem != null).length;
      final ids = await FilesRepository.instance.addFilesWithIds(
        sources,
        patientId: _patientId,
      );
      final added = [
        for (final id in ids) ?await FilesRepository.instance.file(id),
      ];
      if (!mounted) return;
      setState(() => _files.addAll(added));
      if (skipped > 0) {
        _say('$skipped file(s) skipped: type not supported or too large.');
      }
    } catch (e) {
      _say("Couldn't add files: $e");
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _send() async {
    if (_files.isEmpty) {
      _say('Add at least one file.');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final offers = await sendFilesToColleague(
        clinicId: FilesRepository.instance.doctorId,
        colleague: widget.to,
        files: _files,
        subject: _subject.text.trim(),
        note: _note.text.trim(),
      );
      final wifi = offers.isNotEmpty && offers.first.via == FileOfferVia.lan;
      navigator.pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Sent ${_files.length == 1 ? '1 file' : '${_files.length} files'} '
            'to ${widget.to.name} ${wifi ? 'on clinic Wi-Fi' : 'through the cloud'}',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'Undo', onPressed: () => undoSend(offers)),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _say("Couldn't send: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patients = ref.watch(patientsStreamProvider).value ?? const [];
    final patient = patients.where((p) => p.id == _patientId).firstOrNull;
    final patientName = patient?.fullName.trim() ?? '';
    return CruFormDialog(
      title: 'Send to ${widget.to.name}',
      subtitle: patientName.isEmpty ? null : 'For $patientName',
      leading: ColleagueMonogram(name: widget.to.name),
      submitLabel: 'Send',
      busy: _busy,
      dirty:
          _subject.text.isNotEmpty ||
          _note.text.isNotEmpty ||
          _files.length != widget.files.length,
      footerHint:
          'Goes direct on clinic Wi-Fi when you are both on it, otherwise through the cloud.',
      onSubmit: _send,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'Subject',
            controller: _subject,
            optional: true,
            hint: 'e.g. OPG before extraction',
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: CruSpace.s12),
          CruTextField(
            label: 'Note',
            controller: _note,
            optional: true,
            maxLines: 5,
            hint: 'Anything they should know',
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(2000)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: CruSpace.s16),
          Text('Files', style: CruType.groupLabel.tint(c.label2)),
          const SizedBox(height: CruSpace.s8),
          for (final f in _files)
            Padding(
              padding: const EdgeInsets.only(bottom: CruSpace.s8),
              child: Row(
                children: [
                  CruIconTile(icon: fileKindIcon(f.kind), tone: CruTileTone.neutral),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CruType.row.tint(c.label),
                    ),
                  ),
                  const SizedBox(width: CruSpace.s8),
                  Text(
                    PatientFileTypes.sizeLabel(f.sizeBytes),
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                  CruIconButton(
                    icon: CruIcons.close,
                    semanticLabel: 'Remove ${f.name}',
                    size: CruSize.capsule,
                    iconSize: 16,
                    onPressed: _files.length > 1
                        ? () => setState(() => _files.remove(f))
                        : null,
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: CruCapsuleButton(
              label: _adding ? 'Adding…' : 'Add from this PC…',
              icon: CruIcons.plus,
              onPressed: _adding || _busy ? null : _addFromPc,
            ),
          ),
          if (patientName.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s4),
            Text(
              "Files from this PC are also saved to $patientName's files.",
              style: CruType.caption.tint(c.label2),
            ),
          ],
        ],
      ),
    );
  }
}
```

If `FilePicker.pickFiles` is not static in this `file_picker` version, copy the call style from `lib/features/files/presentation/files_actions.dart` (search `pickFiles`).

Check: analyze clean.

## Task 9: Put the row in Files, and show subject and note to the receiver

1. File `lib/features/files/presentation/files_screen.dart`:
   - Add `import 'package:doctor_management_app/features/files/presentation/widgets/colleague_strip.dart';`.
   - In the `top` list, right after the `FilesHeader(...)` entry and before `const SizedBox(height: CruSpace.s20),`, add:
     ```dart
     if (!cruIsPhone(context) && ref.watch(hasColleaguesProvider)) ...[
       const SizedBox(height: CruSpace.s12),
       const ColleagueStrip(),
     ],
     ```
2. File `lib/features/files/presentation/incoming_card.dart`, method `_buildBatchCard`. Right after the `Text('Ready to add to your records for $patientName', ...)` widget, add:
   ```dart
   if (first.subject.isNotEmpty) ...[
     const SizedBox(height: CruSpace.s4),
     Text(first.subject, style: CruType.body.w600.tint(c.label)),
   ],
   if (first.note.isNotEmpty) ...[
     const SizedBox(height: CruSpace.s4),
     Text(
       first.note,
       maxLines: 3,
       overflow: TextOverflow.ellipsis,
       style: CruType.caption.tint(c.label2),
     ),
   ],
   ```
3. File `lib/features/files/presentation/transfers_sheet.dart`, class `_OfferRow`, method `build`:
   - In the `detail` list, add `if (offer.subject.isNotEmpty) offer.subject,` as the second item (right after the `'Waiting'` line).
   - Under the detail `Text(...)` in the `Column`, add:
     ```dart
     if (offer.note.isNotEmpty) ...[
       const SizedBox(height: CruSpace.s2),
       Text(
         offer.note,
         maxLines: 2,
         overflow: TextOverflow.ellipsis,
         style: CruType.caption.tint(c.label3),
       ),
     ],
     ```
4. File `test/features/files/file_offers_test.dart`: add one test inside the existing `group(...)`, after the last test:
   ```dart
   test('subject and note survive Firestore and Wi-Fi JSON', () {
     final offer = FileOffer(
       id: 'o1',
       clinicId: 'c1',
       from: 'a',
       to: 'b',
       batchId: 'b1',
       fileId: 'f1',
       sha256: 'c' * 64,
       sizeBytes: 1,
       contentType: 'application/pdf',
       patientId: 'p1',
       name: 'x.pdf',
       thumb: '',
       status: FileOfferStatus.sent,
       via: FileOfferVia.cloud,
       createdAt: DateTime.utc(2026, 10, 28),
       expireAt: DateTime.utc(2026, 11, 27),
       subject: 'OPG',
       note: 'Before extraction',
     );
     final back = FileOffer.fromFirestore(
       id: 'o1',
       clinicId: 'c1',
       data: jsonDecode(jsonEncode(offer.toJson())) as Map<String, dynamic>,
     );
     expect(back.subject, 'OPG');
     expect(back.note, 'Before extraction');
   });
   ```

Check: analyze clean.

---

## Checks (run once, after all tasks)

1. From `CruDoc/`:
   ```
   flutter analyze lib/features/files test/features/files
   ```
   Fix any error or warning in lines you wrote. List others in the report without fixing them.
2. ```
   flutter test --concurrency=1 test/features/files/file_offers_test.dart
   ```
   All must pass. Never run several `flutter test` commands at the same time (they crash on sqlite3.dll).
3. Run the Windows app (`flutter run -d windows`), sign in with a clinic account that has at least one colleague, open Files, and try:
   - The row shows under the header buttons; it is not on a phone-width window.
   - Drag a file onto a colleague and drop: snackbar "Sent … to …" with Undo.
   - Drag, hold 1 s: the avatar lifts and says "Swipe right for a note". Move right: the compose popup opens with the file. Add a subject, a note, and a file from the PC; Send.
   - Drag onto a colleague without clinical access (if there is one): it dims and shows the reason; the drop does nothing.
   If you can't sign in or there is no colleague, write that down and skip this check.

## GATE: stop here and report

Report: each task done or skipped (with what you saw), the Check results, and anything that looked wrong when you ran the app. Do not commit, push or deploy.

For Soham, after the report (not for Antigravity): bring the report to Claude. Claude reviews and polishes (motion, drop feedback, anything missed), adds Firestore rule limits for `subject` and `note`, and commits.

---

## Done

(nothing yet)
