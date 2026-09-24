import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/imaging/rad_pixels.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/annotation_painter.dart';
import 'package:doctor_management_app/features/radiology/viewer/image_render.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _thumbMax = 208;

/// Decodes an image file and renders a small preview at its default
/// window (runs in an isolate).
RadRgba _thumbRgba(String path, RadFileKind kind) {
  final px = decodeRadPixels(File(path).readAsBytesSync(), kind);
  final step = math.max(1, (math.max(px.width, px.height) / _thumbMax).ceil());
  final (c, w) = px.defaultWindow;
  return renderDisplay(px, px.values, RadDisplay(center: c, width: w, invert: px.invert), step: step);
}

Future<RadRgba> _thumbInIsolate(String path, RadFileKind kind) =>
    Isolate.run(() => _thumbRgba(path, kind));

/// Thumbnail previews, made one at a time in the background.
class RadThumbCache extends ChangeNotifier {
  RadThumbCache(this._fileOf);

  final Future<File> Function(RadStudy s, String relativePath) _fileOf;
  final _images = <String, ui.Image>{};
  final _failed = <String>{};
  final _queued = <String>{};
  final _queue = <(RadStudy, RadImageRef)>[];
  bool _busy = false;
  bool _disposed = false;

  static String _key(String studyId, String imageId) => '$studyId/$imageId';

  ui.Image? image(String studyId, String imageId) => _images[_key(studyId, imageId)];
  bool failed(String studyId, String imageId) => _failed.contains(_key(studyId, imageId));

  void request(RadStudy s, RadImageRef i) {
    final key = _key(s.id, i.id);
    if (i.compressed || _images.containsKey(key) || _failed.contains(key) || !_queued.add(key)) {
      return;
    }
    _queue.add((s, i));
    _pump();
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    while (_queue.isNotEmpty && !_disposed) {
      final (s, i) = _queue.removeAt(0);
      final key = _key(s.id, i.id);
      try {
        final f = await _fileOf(s, i.path);
        final rgba = await _thumbInIsolate(f.path, i.kind);
        final image = await radImageFromRgba(rgba);
        if (_disposed) {
          image.dispose();
          break;
        }
        _images[key] = image;
      } catch (_) {
        _failed.add(key);
      }
      if (!_disposed) notifyListeners();
    }
    _busy = false;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

/// The left strip: the study's images by series (and the earlier study's
/// when comparing). Click opens an image in the active pane; drag one
/// onto any pane.
class RadThumbnailStrip extends StatelessWidget {
  const RadThumbnailStrip({
    super.key,
    required this.study,
    required this.compare,
    required this.cache,
    required this.shown,
    required this.active,
    required this.onOpen,
  });

  static const width = 128.0;

  final RadStudy study;
  final RadStudy? compare;
  final RadThumbCache cache;

  /// "studyId/imageId" of every image on screen, and the active pane's.
  final Set<String> shown;
  final String active;
  final void Function(String studyId, String imageId) onOpen;

  List<Widget> _section(BuildContext context, RadStudy s, String title) {
    final c = context.cru;
    final bySeries = <String, List<RadImageRef>>{};
    for (final i in s.images) {
      (bySeries[i.seriesUid] ??= []).add(i);
    }
    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(CruSpace.s12, CruSpace.s16, CruSpace.s12, CruSpace.s4),
        child: Text(title, style: CruType.groupLabel.tint(c.label3), maxLines: 2),
      ),
    ];
    final stacks = radStacks(s);
    var n = 0;
    for (final e in bySeries.entries) {
      final list = [...e.value]..sort((a, b) => a.instanceNumber.compareTo(b.instanceNumber));
      final stack = stacks[e.key];
      if (bySeries.length > 1) {
        final label = list.first.seriesDescription.isNotEmpty
            ? list.first.seriesDescription
            : 'Series ${bySeries.keys.toList().indexOf(e.key) + 1}';
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(CruSpace.s12, CruSpace.s8, CruSpace.s12, CruSpace.s2),
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: CruType.micro.tint(c.label2)),
        ));
      }
      if (stack != null) {
        // A slice stack gets one thumbnail: its middle slice.
        final mid = s.images.firstWhere((i) => i.id == stack[stack.length ~/ 2]);
        n++;
        cache.request(s, mid);
        out.add(_Thumb(
          study: s,
          image: mid,
          number: n,
          slices: stack.length,
          cache: cache,
          shown: stack.any((id) => shown.contains('${s.id}/$id')),
          active: stack.any((id) => active == '${s.id}/$id'),
          onOpen: () => onOpen(s.id, mid.id),
        ));
        continue;
      }
      for (final i in list) {
        n++;
        cache.request(s, i);
        out.add(_Thumb(
          study: s,
          image: i,
          number: n,
          cache: cache,
          shown: shown.contains('${s.id}/${i.id}'),
          active: active == '${s.id}/${i.id}',
          onOpen: () => onOpen(s.id, i.id),
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final other = compare;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.separator)),
      ),
      child: ListenableBuilder(
        listenable: cache,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: CruSpace.s16),
          children: [
            ..._section(context, study, RadFormat.images(study.images.length)),
            if (other != null)
              ..._section(context, other, 'Earlier · ${RadFormat.date(other.studyDate)}'),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.study,
    required this.image,
    required this.number,
    required this.cache,
    required this.shown,
    required this.active,
    required this.onOpen,
    this.slices = 0,
  });

  final RadStudy study;
  final RadImageRef image;
  final int number;

  /// Slices in the stack this thumbnail stands for (0 = one image).
  final int slices;
  final RadThumbCache cache;
  final bool shown;
  final bool active;
  final VoidCallback onOpen;

  static const _w = 104.0, _h = 80.0;

  Widget _tile(BuildContext context, {bool hovered = false}) {
    final c = context.cru;
    final ui.Image? preview = cache.image(study.id, image.id);
    final unsupported = image.compressed || cache.failed(study.id, image.id);
    return Container(
      width: _w,
      height: _h,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: RadInk.viewport,
        shape: cruShape(
          CruRadius.iconTile,
          side: BorderSide(
            color: active ? c.accent : (shown || hovered ? c.label3 : c.hairline),
            width: active ? 2 : 1,
          ),
        ),
      ),
      alignment: Alignment.center,
      child: preview != null
          ? RawImage(image: preview, fit: BoxFit.contain, width: _w, height: _h)
          : Padding(
              padding: const EdgeInsets.all(CruSpace.s6),
              child: Text(
                unsupported ? 'Not supported' : '',
                textAlign: TextAlign.center,
                style: CruType.micro.tint(RadInk.overlayQuiet),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final caption = [
      '$number',
      if (slices > 1) '$slices slices',
      if (image.frames > 1) '${image.frames} frames',
      if (image.compressed) 'Not supported',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CruSpace.s12, vertical: CruSpace.s4),
      child: Draggable<RadImageDrag>(
        data: RadImageDrag(study.id, image.id),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Opacity(opacity: 0.85, child: _tile(context)),
        child: CruPressable(
          onTap: onOpen,
          semanticLabel: 'Image $number',
          tooltip: image.seriesDescription.isEmpty ? null : image.seriesDescription,
          builder: (context, hovered) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tile(context, hovered: hovered),
              const SizedBox(height: CruSpace.s4),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.micro.tabular.tint(active ? c.label : c.label2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
