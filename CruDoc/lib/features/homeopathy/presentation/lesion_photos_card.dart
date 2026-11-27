import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/features/dental/records/dental_photo_cloud_sync.dart';
import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/homeopathy/domain/lesion_photo_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Photographs of a skin case, followed per site.
///
/// Skin and wart cases are the ones where the patient's own impression and
/// the record disagree most often — "it's the same" six weeks on, against
/// two photographs that are not. So the card is organised by site and leads
/// with how long each has been followed, and the comparison only ever puts
/// two photographs of the same place side by side.
class LesionPhotosCard extends ConsumerWidget {
  const LesionPhotosCard({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final recs = ref.watch(
      patientRecordsProvider((
        patientId: patientId,
        kind: RecKind.homeoLesionPhoto,
      )),
    );
    final sets = lesionPhotoSets(recs.value ?? const <DentalRecord>[]);
    final series = lesionSeriesOf(sets);

    return CruCard(
      semanticLabel: 'Skin photographs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CruIconTile(icon: CruIcons.scan, tone: CruTileTone.neutral),
              const SizedBox(width: CruSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Skin photographs',
                      style: CruType.headline.w600.tint(c.label),
                    ),
                    const SizedBox(height: CruSpace.s2),
                    Text(
                      series.isEmpty
                          ? 'Follow a lesion across visits'
                          : '${series.length} site'
                                '${series.length == 1 ? '' : 's'} · '
                                '${sets.length} visit'
                                '${sets.length == 1 ? '' : 's'}',
                      style: CruType.caption.tabular.tint(c.label2),
                    ),
                  ],
                ),
              ),
              CruCapsuleButton(
                label: series.isEmpty ? 'Add photos' : '+ Visit',
                icon: series.isEmpty ? CruIcons.plus : null,
                onPressed: () => showLesionVisitSheet(
                  context,
                  ref,
                  patientId: patientId,
                  known: knownLesionSites(sets),
                ),
              ),
            ],
          ),
          for (final s in series)
            InkWell(
              borderRadius: BorderRadius.circular(CruRadius.control),
              onTap: () => showLesionSeriesSheet(context, s, patientName),
              child: Padding(
                padding: const EdgeInsets.only(top: CruSpace.s12),
                child: Row(
                  children: [
                    _Thumb(path: s.latest.path),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.body.w600.tint(c.label),
                          ),
                          Text(
                            lesionSeriesLine(s),
                            style: CruType.caption.tabular.tint(c.label2),
                          ),
                        ],
                      ),
                    ),
                    if (s.canCompare)
                      Text('Compare', style: CruType.caption.tint(c.accent)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small square of a photograph, or a placeholder when the file has gone.
///
/// A missing file is shown as missing rather than as a blank square: the
/// record says there is a photograph, and if the file is not there the
/// clinic needs to see that.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.path, this.size = 40});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final file = File(path);
    final exists = file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(CruRadius.iconTile),
      child: SizedBox(
        width: size,
        height: size,
        child: exists
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: c.inset,
                child: Center(
                  child: CruIcon(CruIcons.warning, size: 16, color: c.label3),
                ),
              ),
      ),
    );
  }
}

/// Record a visit: which sites were photographed, and the photographs.
Future<void> showLesionVisitSheet(
  BuildContext context,
  WidgetRef ref, {
  required String patientId,
  required List<({String key, String label})> known,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _LesionVisitSheet(patientId: patientId, known: known),
);

class _LesionVisitSheet extends ConsumerStatefulWidget {
  const _LesionVisitSheet({required this.patientId, required this.known});

  final String patientId;
  final List<({String key, String label})> known;

  @override
  ConsumerState<_LesionVisitSheet> createState() => _LesionVisitSheetState();
}

class _LesionVisitSheetState extends ConsumerState<_LesionVisitSheet> {
  final _newSite = TextEditingController();
  final _notes = TextEditingController();
  final _siteForm = GlobalKey<FormState>();
  DateTime _date = DateTime.now();

  /// Site key to label, for this visit.
  final Map<String, String> _sites = {};

  /// Site key to the file picked for it.
  final Map<String, String> _picked = {};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The sites already being followed come pre-selected, because a visit
    // that does not re-photograph them breaks their series.
    for (final s in widget.known) {
      _sites[s.key] = s.label;
    }
  }

  @override
  void dispose() {
    _newSite.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _addSite() {
    if (!(_siteForm.currentState?.validate() ?? false)) return;
    final label = _newSite.text.trim();
    final key = lesionSiteKey(label);
    setState(() {
      _sites[key] = label;
      _newSite.clear();
    });
  }

  Future<void> _pick(String key) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      dialogTitle: 'Photograph of ${_sites[key]}',
    );
    final source = result?.files.singleOrNull?.path;
    if (source == null) return;
    setState(() => _picked[key] = source);
  }

  Future<void> _save() async {
    final withPhotos = {
      for (final e in _picked.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value,
    };
    if (withPhotos.isEmpty) return;
    setState(() => _saving = true);

    // The record is created first so its id can name the folder, which keeps
    // one visit's photographs together and makes an orphaned file obvious.
    var record = DentalRecord.create(
      widget.patientId,
      RecKind.homeoLesionPhoto,
      LesionPhotoSet.toData(
        date: _date,
        notes: _notes.text.trim(),
        sites: {for (final key in withPhotos.keys) key: _sites[key] ?? key},
        photos: const {},
      ),
    );

    final dir = Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'homeopathy',
        'lesions',
        widget.patientId,
        record.id,
      ),
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final stored = <String, String>{};
    for (final e in withPhotos.entries) {
      // Copied as it came off the camera: a photograph is evidence, so
      // nothing re-encodes, crops or rotates it.
      final dest = p.join(dir.path, '${e.key}${p.extension(e.value)}');
      await File(e.value).copy(dest);
      stored[e.key] = dest;
    }

    record = record.copyWith(data: {...record.data, 'photos': stored});
    await saveDentalRecord(ref, record);

    for (final e in stored.entries) {
      unawaited(
        DentalPhotoCloudSync.enqueuePhoto(
          record: record,
          slot: e.key,
          localPath: e.value,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final ready = _picked.values.any((v) => v.trim().isNotEmpty);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          0,
          CruSpace.s16,
          CruSpace.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Photograph the skin', style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s4),
            Text(
              'Same spot, same distance each visit.',
              style: CruType.caption.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            CruCapsuleButton(
              label: 'Visit of ${DentalFormat.date(_date)}',
              icon: CruIcons.calendar,
              onPressed: () async {
                final picked = await pickDentalDate(
                  context,
                  initial: _date,
                  last: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: CruSpace.s16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final key in _sites.keys)
                      Padding(
                        padding: const EdgeInsets.only(bottom: CruSpace.s12),
                        child: Row(
                          children: [
                            if (_picked[key] case final path?)
                              _Thumb(path: path, size: 36)
                            else
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: c.inset,
                                  borderRadius: BorderRadius.circular(
                                    CruRadius.iconTile,
                                  ),
                                ),
                              ),
                            const SizedBox(width: CruSpace.s12),
                            Expanded(
                              child: Text(
                                _sites[key]!,
                                style: CruType.callout.tint(c.label),
                              ),
                            ),
                            CruCapsuleButton(
                              label: _picked.containsKey(key)
                                  ? 'Replace'
                                  : 'Photograph',
                              onPressed: () => _pick(key),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Form(
                            key: _siteForm,
                            child: CruTextField(
                              label: 'Another site',
                              controller: _newSite,
                              hint: 'Left thumb, scalp, right elbow',
                              textCapitalization: TextCapitalization.sentences,
                              validator: (v) =>
                                  lesionSiteKey((v ?? '').trim()).isEmpty
                                  ? 'Give the site a name, such as "left thumb".'
                                  : null,
                              onSubmitted: (_) => _addSite(),
                            ),
                          ),
                        ),
                        const SizedBox(width: CruSpace.s8),
                        CruCapsuleButton(label: 'Add', onPressed: _addSite),
                      ],
                    ),
                    const SizedBox(height: CruSpace.s12),
                    CruMoreFields(
                      label: 'Note',
                      open: _notes.text.isNotEmpty,
                      children: [
                        CruTextField(
                          label: 'Note',
                          controller: _notes,
                          hint: 'What the lesion looks like today',
                          optional: true,
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: CruSpace.s16),
            CruButton(
              label: _saving ? 'Saving…' : 'Save visit',
              expand: true,
              // Nothing is saved without a photograph: a visit record with
              // no picture is a row that looks like evidence and is not.
              onPressed: _saving || !ready ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// One site across visits, with the first and latest side by side.
Future<void> showLesionSeriesSheet(
  BuildContext context,
  LesionSeries series,
  String patientName,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _LesionSeriesSheet(series: series, patientName: patientName),
);

class _LesionSeriesSheet extends StatefulWidget {
  const _LesionSeriesSheet({required this.series, required this.patientName});

  final LesionSeries series;
  final String patientName;

  @override
  State<_LesionSeriesSheet> createState() => _LesionSeriesSheetState();
}

class _LesionSeriesSheetState extends State<_LesionSeriesSheet> {
  late int _leftIndex = 0;
  late int _rightIndex = widget.series.shots.length - 1;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final shots = widget.series.shots;
    final left = shots[_leftIndex];
    final right = shots[_rightIndex];

    Widget pane(LesionShot shot, String caption) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(caption, style: CruType.groupLabel.tint(c.label2)),
          const SizedBox(height: CruSpace.s4),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CruRadius.control),
              child: File(shot.path).existsSync()
                  ? Image.file(File(shot.path), fit: BoxFit.cover)
                  : ColoredBox(
                      color: c.inset,
                      child: Center(
                        child: Text(
                          'File missing',
                          style: CruType.caption.tint(c.label3),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: CruSpace.s4),
          Text(
            DentalFormat.date(shot.date),
            style: CruType.caption.tabular.tint(c.label),
          ),
        ],
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CruSpace.s16,
          0,
          CruSpace.s16,
          CruSpace.s16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.series.label, style: CruType.headline.tint(c.label)),
            const SizedBox(height: CruSpace.s2),
            Text(
              lesionSeriesLine(widget.series),
              style: CruType.caption.tabular.tint(c.label2),
            ),
            const SizedBox(height: CruSpace.s16),
            if (widget.series.canCompare)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pane(left, 'EARLIER'),
                  const SizedBox(width: CruSpace.s12),
                  pane(right, 'LATER'),
                ],
              )
            else
              // One photograph: shown on its own rather than doubled up to
              // fill a before-and-after frame.
              Row(children: [pane(shots.single, 'ONLY PHOTOGRAPH')]),
            if (widget.series.canCompare) ...[
              const SizedBox(height: CruSpace.s16),
              Text('PICK TWO VISITS', style: CruType.groupLabel.tint(c.label2)),
              const SizedBox(height: CruSpace.s8),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: shots.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: CruSpace.s8),
                  itemBuilder: (_, i) {
                    final selected = i == _leftIndex || i == _rightIndex;
                    return InkWell(
                      borderRadius: BorderRadius.circular(CruRadius.iconTile),
                      // Tapping sets the earlier or later pane depending on
                      // which side of the current pair it falls, so a pair
                      // can be walked along without a mode to switch.
                      onTap: () => setState(() {
                        if (i <= _leftIndex) {
                          _leftIndex = i;
                        } else {
                          _rightIndex = i;
                        }
                        if (_leftIndex >= _rightIndex) {
                          _leftIndex = i == 0 ? 0 : i - 1;
                          _rightIndex = i;
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            CruRadius.iconTile + 2,
                          ),
                          border: Border.all(
                            color: selected ? c.accent : c.hairline,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: _Thumb(path: shots[i].path, size: 48),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (right.notes.trim().isNotEmpty) ...[
              const SizedBox(height: CruSpace.s12),
              Text(right.notes.trim(), style: CruType.caption.tint(c.label2)),
            ],
          ],
        ),
      ),
    );
  }
}
