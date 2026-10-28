import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/people/crudoc_id.dart';
import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/referrals/referral_network.dart'
    show searchDirectory;
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Finds a doctor on CruDoc to send a consult to: anyone by their exact
/// CruDoc ID (listed or not, in any clinic), or the listed doctors by name,
/// @handle, specialty or city. Returns the one picked, or null.
Future<CrudocPerson?> showDoctorPicker(
  BuildContext context, {
  String initialQuery = '',
}) => showDialog<CrudocPerson>(
  context: context,
  builder: (_) => _DoctorPickerDialog(initialQuery: initialQuery),
);

/// "Dr. Smit Patil", without doubling a "Dr." the name already has.
String _drName(String name) {
  final n = name.trim().isEmpty ? 'Doctor' : name.trim();
  return RegExp(r'^dr\.?\s', caseSensitive: false).hasMatch(n) ? n : 'Dr. $n';
}

class _DoctorPickerDialog extends StatefulWidget {
  const _DoctorPickerDialog({this.initialQuery = ''});

  final String initialQuery;

  @override
  State<_DoctorPickerDialog> createState() => _DoctorPickerDialogState();
}

class _DoctorPickerDialogState extends State<_DoctorPickerDialog> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  List<CrudocPerson> _results = const [];
  bool _searching = false;
  String _searched = '';

  /// Why a typed CruDoc ID gave no doctor (not found, not a doctor...).
  String? _idNote;

  /// The directory search failed and nothing else was found.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    setState(() {
      _searching = true;
      _idNote = null;
      _failed = false;
    });
    // A CruDoc ID finds that one person, listed or not. A name can look
    // like an ID too, so the directory is searched either way, on its own:
    // a directory error mustn't lose an ID hit.
    CrudocPerson? byId;
    String? idNote;
    if (looksLikeCrudocId(q)) {
      try {
        final person = await CrudocIdApi.find(q);
        if (person.isDoctor) {
          byId = person;
        } else {
          idNote =
              "${person.name.isEmpty ? 'This person' : person.name} is not a "
              "doctor, so they can't take consults.";
        }
      } on CrudocIdException catch (e) {
        idNote = e.message;
      }
    }
    var listed = const <CruDocDoctor>[];
    var failed = false;
    try {
      listed = await searchDirectory(
        q,
        selfUid: FirebaseAuth.instance.currentUser?.uid,
      );
    } catch (e) {
      debugPrint('[doctorPicker] directory search failed: $e');
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _results = [
        ?byId,
        for (final d in listed)
          if (d.uid != byId?.uid)
            CrudocPerson(doctor: d, crudocId: '', isDoctor: true),
      ];
      _idNote = idNote;
      _failed = failed && _results.isEmpty;
      _searching = false;
      _searched = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final idNote = _idNote;
    return DentalPanelDialog(
      title: 'Find a doctor on CruDoc',
      subtitle: 'Anyone by their CruDoc ID, or listed doctors by name',
      leading: const CruIconTile(
        icon: CruIcons.search,
        tone: CruTileTone.neutral,
      ),
      width: 520,
      footer: CruButton(
        label: 'Close',
        kind: CruButtonKind.secondary,
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CruTextField(
            label: 'CruDoc ID, name, @handle, specialty or city',
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            trailing: CruCapsuleButton(
              label: _searching ? 'Searching…' : 'Search',
              icon: CruIcons.search,
              onPressed: _searching ? null : _search,
            ),
          ),
          const SizedBox(height: CruSpace.s12),
          if (!_searching && idNote != null) ...[
            Text(idNote, style: CruType.caption.tint(c.label2)),
            const SizedBox(height: CruSpace.s8),
          ],
          if (_results.isEmpty &&
              _searched.isNotEmpty &&
              !_searching &&
              idNote == null)
            Text(
              _failed
                  ? "Couldn't search right now. Try again."
                  : 'No listed doctor matches "$_searched". Ask them for '
                        'their CruDoc ID (Settings › Profile): it finds them '
                        "even if they aren't listed.",
              style: CruType.caption.tint(c.label2),
            ),
          for (final p in _results)
            DentalListRow(
              semanticLabel: p.name,
              onTap: () => Navigator.of(context).pop(p),
              child: Row(
                children: [
                  CruMonogram(name: p.name),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _drName(p.name),
                          style: CruType.callout.w600.tint(c.label),
                        ),
                        Text(
                          [
                            if (p.crudocId.isNotEmpty)
                              'CruDoc ID ${p.crudocId}',
                            if (p.doctor.handle.isNotEmpty)
                              '@${p.doctor.handle}',
                            if (p.doctor.specialty.isNotEmpty)
                              p.doctor.specialty,
                            if (p.doctor.city.isNotEmpty) p.doctor.city,
                          ].join(' · '),
                          style: CruType.caption.tabular.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
