import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/services/local_storage_manager.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Settings → Storage: how much space CruDoc may use on this device.
///
/// The limit is this device's own (see [LocalStorageManager]); a phone and
/// a computer signed in to the same account each keep their own.
class StorageSection extends StatefulWidget {
  const StorageSection({super.key, this.manager});

  /// For tests; the app's instance otherwise.
  final LocalStorageManager? manager;

  @override
  State<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<StorageSection> {
  LocalStorageManager get _m => widget.manager ?? LocalStorageManager.instance;
  static const _choices = LocalStorageManager.limitChoices;

  LocalStorageReport? _report;
  int _limit = 0;

  /// The slider's position while it is being dragged.
  double? _dragging;
  bool _freeing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final limit = await _m.limitBytes();
    final report = await _m.report();
    if (!mounted) return;
    setState(() {
      _limit = limit;
      _report = report;
    });
  }

  int _indexOf(int limit) {
    final i = _choices.indexOf(limit);
    return i < 0 ? _choices.length - 1 : i;
  }

  Future<void> _setLimit(int index) async {
    final limit = _choices[index];
    setState(() {
      _limit = limit;
      _dragging = null;
    });
    await _m.setLimitBytes(limit);
  }

  Future<void> _freeUp() async {
    setState(() => _freeing = true);
    final result = await _m.enforce();
    await _load();
    if (!mounted) return;
    setState(() => _freeing = false);
    final freed = result.removedFiles == 0
        ? 'Nothing could be removed yet.'
        : 'Freed ${formatBytes(result.freedBytes)} '
              '(${result.removedFiles} '
              '${result.removedFiles == 1 ? 'file' : 'files'}). '
              'They download again when opened.';
    final still = result.withinLimit
        ? ''
        : result.skippedUnsafe > 0
        ? ' ${result.skippedUnsafe} more could not be confirmed in the cloud '
              'yet (still uploading, or offline) and were kept.'
        : ' The rest is patient records, uploads still waiting, or files '
              'that are only on this device, which are never removed.';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$freed$still'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final report = _report;
    final index = _dragging ?? _indexOf(_limit).toDouble();
    final shown = _choices[index.round()];
    final over =
        report != null && _limit > 0 && report.totalBytes > _limit;

    return CruCard(
      semanticLabel: 'Storage on this device',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Storage on this device', style: CruType.headline.tint(c.label)),
          const SizedBox(height: CruSpace.s4),
          Text(
            'How much space CruDoc may use here. This applies to this device '
            'only: your other phones and computers keep their own limit.',
            style: CruType.text.tint(c.label2),
          ),
          const SizedBox(height: CruSpace.s20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                report == null ? 'Adding up…' : formatBytes(report.totalBytes),
                style: CruType.title.tabular.tint(c.label),
              ),
              const SizedBox(width: CruSpace.s8),
              Expanded(
                child: Text(
                  _limit > 0 ? 'of ${formatBytes(_limit)} used' : 'used',
                  style: CruType.text.tint(c.label2),
                ),
              ),
            ],
          ),
          if (report != null && _limit > 0) ...[
            const SizedBox(height: CruSpace.s8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (report.totalBytes / _limit).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: c.inset,
                color: over ? c.amberText : c.accent,
              ),
            ),
          ],
          const SizedBox(height: CruSpace.s20),
          Text('LIMIT', style: CruType.groupLabel.tint(c.label3)),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: index,
                  min: 0,
                  max: (_choices.length - 1).toDouble(),
                  divisions: _choices.length - 1,
                  label: _label(shown),
                  activeColor: c.accent,
                  inactiveColor: c.inset,
                  semanticFormatterCallback: (v) => _label(_choices[v.round()]),
                  onChanged: (v) => setState(() => _dragging = v),
                  onChangeEnd: (v) => _setLimit(v.round()),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  _label(shown),
                  textAlign: TextAlign.end,
                  style: CruType.row.tabular.tint(c.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: CruSpace.s12),
          if (report != null) ...[
            _Row(
              title: 'Files and scans also in the cloud',
              detail:
                  'Removed oldest first when over the limit, once the cloud '
                  'copy is confirmed. They download again when opened.',
              value: formatBytes(report.cloudCopyBytes),
            ),
            const CruSeparator(),
            _Row(
              title: 'Previews and viewing files',
              detail: 'Fetched again when needed. Removed first.',
              value: formatBytes(report.cacheBytes),
            ),
            const CruSeparator(),
            _Row(
              title: 'Always kept on this device',
              detail:
                  'Patient names and details, records, uploads still waiting, '
                  'and files that are never uploaded. Never removed.',
              value: formatBytes(report.keptBytes),
            ),
          ],
          const SizedBox(height: CruSpace.s16),
          // A wrap: on a phone the note drops under the button.
          Wrap(
            spacing: CruSpace.s12,
            runSpacing: CruSpace.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CruButton(
                label: _freeing ? 'Freeing space…' : 'Free up space now',
                kind: CruButtonKind.secondary,
                onPressed: _freeing || !over ? null : _freeUp,
              ),
              Text(
                _limit <= 0
                    ? 'No limit set: nothing is removed.'
                    : over
                    ? 'Over the limit. Space is also freed automatically.'
                    : 'Within the limit.',
                style: CruType.caption.tint(c.label2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _label(int limit) => limit <= 0 ? 'No limit' : formatBytes(limit);
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.detail, required this.value});

  final String title;
  final String detail;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: CruType.row.tint(c.label)),
                const SizedBox(height: CruSpace.s2),
                Text(detail, style: CruType.caption.tint(c.label2)),
              ],
            ),
          ),
          const SizedBox(width: CruSpace.s16),
          Text(value, style: CruType.row.tabular.tint(c.label)),
        ],
      ),
    );
  }
}

/// 1536 -> "1.5 KB", 3221225472 -> "3 GB".
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final text = u == 0 || v >= 100 || v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);
  return '$text ${units[u]}';
}
