
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

const _lastCameraKey = 'intraoral_last_camera';

const _upperTeeth = [
  18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28, //
];
const _lowerTeeth = [
  48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38, //
];

/// Foot pedals usually act as a keyboard key; these all take a photo.
final _captureKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.mediaPlayPause,
};

class _Shot {
  _Shot(this.bytes, this.tooth);
  final Uint8List bytes;
  int? tooth; // FDI number, null for full mouth
}

/// Live intraoral (USB/UVC) camera: capture photos, tag each with an FDI
/// tooth, then save them all to the patient's Files.
class IntraoralCameraScreen extends StatefulWidget {
  const IntraoralCameraScreen({super.key, required this.patient});

  final Patient patient;

  static Future<void> open(BuildContext context, Patient patient) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => IntraoralCameraScreen(patient: patient),
        ),
      );

  @override
  State<IntraoralCameraScreen> createState() => _IntraoralCameraScreenState();
}

class _IntraoralCameraScreenState extends State<IntraoralCameraScreen> {
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selected;
  CameraController? _controller;
  String? _error;
  bool _loading = true;
  bool _capturing = false;
  bool _saving = false;
  int _saved = 0;
  bool _done = false;
  int? _tooth; // tooth for the next capture
  final List<_Shot> _shots = [];
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller?.dispose();
    super.dispose();
  }

  String _label(CameraDescription c, int i) =>
      c.name.trim().isEmpty ? 'Camera ${i + 1}' : c.name;

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        throw CameraException('none', 'No camera found');
      }
      _cameras = cams;
      String? last;
      try {
        last = (await SharedPreferences.getInstance()).getString(
          _lastCameraKey,
        );
      } catch (_) {}
      // Prefer the last used one; else an external one; else the first.
      _selected =
          cams.where((c) => c.name == last).firstOrNull ??
          cams.where((c) => c.lensDirection == CameraLensDirection.external)
              .firstOrNull ??
          cams.first;
      await _open(_selected!);
    } on CameraException catch (e) {
      _fail(e);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'The camera could not be opened.';
          _loading = false;
        });
      }
    }
  }

  void _fail(CameraException e) {
    if (!mounted) return;
    final denied = e.code.toLowerCase().contains('access');
    setState(() {
      _error = e.code == 'none'
          ? 'No camera found. Plug in the intraoral camera and try again.'
          : denied
          ? 'Camera permission was refused. Allow camera access in Settings, '
                'then try again.'
          : 'The camera could not be opened. Check it is plugged in and not '
                'used by another app.';
      _loading = false;
    });
  }

  Future<void> _open(CameraDescription cam) async {
    final old = _controller;
    final next = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: false,
    );
    setState(() {
      _controller = null;
      _loading = true;
      _error = null;
    });
    await old?.dispose();
    try {
      await next.initialize();
    } on CameraException catch (e) {
      await next.dispose();
      _fail(e);
      return;
    }
    if (!mounted) {
      await next.dispose();
      return;
    }
    try {
      (await SharedPreferences.getInstance()).setString(
        _lastCameraKey,
        cam.name,
      );
    } catch (_) {}
    setState(() {
      _controller = next;
      _selected = cam;
      _loading = false;
    });
    _focus.requestFocus();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing || _saving) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _shots.add(_Shot(bytes, _tooth)));
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo failed. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent && _captureKeys.contains(e.logicalKey)) {
      _capture();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _save() async {
    if (_shots.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _saved = 0;
    });
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < _shots.length; i++) {
        final s = _shots[i];
        final tag = s.tooth == null ? 'full mouth' : 'tooth ${s.tooth}';
        await FilesRepository.instance.addFiles(
          [
            FileSource(
              name: 'Intraoral · $tag · ${stamp + i}.jpg',
              sizeBytes: s.bytes.length,
              bytes: s.bytes,
              teeth: [if (s.tooth != null) s.tooth!],
            ),
          ],
          patientId: widget.patient.id,
        );
        if (mounted) setState(() => _saved = i + 1);
      }
      if (!mounted) return;
      setState(() {
        _done = true;
        _saving = false;
      });
      final n = _shots.length;
      _shots.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$n photo${n == 1 ? '' : 's'} saved to Files.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Nothing was lost; try again.')),
      );
    }
  }

  Future<bool> _confirmLeave() async {
    if (_shots.isEmpty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard photos?'),
        content: Text(
          '${_shots.length} photo${_shots.length == 1 ? ' is' : 's are'} '
          'not saved to the patient yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _editShot(int index) async {
    final s = _shots[index];
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tooth for this photo', style: CruType.headline),
              const SizedBox(height: 12),
              _ToothPicker(
                selected: s.tooth,
                onPick: (t) => Navigator.pop(ctx, t == null ? 'none' : '$t'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete photo'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() {
      if (action == 'delete') {
        _shots.removeAt(index);
      } else {
        s.tooth = action == 'none' ? null : int.parse(action);
      }
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final preview = _preview(c);
    final picker = _ToothPicker(
      selected: _tooth,
      onPick: (t) {
        setState(() => _tooth = t);
        _focus.requestFocus();
      },
    );

    return PopScope(
      canPop: _shots.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: c.canvas,
          appBar: AppBar(
            backgroundColor: c.canvas,
            title: Text('Intraoral camera · ${widget.patient.firstName} ${widget.patient.lastName}'),
            actions: [
              if (_cameras.length > 1)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: DropdownButton<CameraDescription>(
                    value: _selected,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var i = 0; i < _cameras.length; i++)
                        DropdownMenuItem(
                          value: _cameras[i],
                          child: Text(
                            _label(_cameras[i], i),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (cam) {
                      if (cam != null) _open(cam);
                    },
                  ),
                ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: preview),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 420,
                              child: SingleChildScrollView(child: picker),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: preview),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 150,
                              child: SingleChildScrollView(child: picker),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                _strip(c),
                const SizedBox(height: 8),
                _actions(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(CruColors c) {
    final cam = _controller;
    Widget child;
    if (_loading) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_error != null || cam == null) {
      child = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 40, color: c.label2),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error ?? 'No camera.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.label2),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _start, child: const Text('Retry')),
          ],
        ),
      );
    } else {
      child = Center(
        child: AspectRatio(
          aspectRatio: cam.value.aspectRatio,
          child: CameraPreview(cam),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(child: child),
      ),
    );
  }

  Widget _strip(CruColors c) {
    if (_shots.isEmpty) {
      return SizedBox(
        height: 24,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _done
                ? 'Saved to the patient\'s Files.'
                : 'Press Space, Enter or the foot pedal to capture.',
            style: TextStyle(color: c.label2),
          ),
        ),
      );
    }
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _shots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = _shots[i];
          return GestureDetector(
            onTap: _saving ? null : () => _editShot(i),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    s.bytes,
                    width: 112,
                    height: 84,
                    fit: BoxFit.cover,
                    cacheWidth: 224,
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.tooth == null ? 'Mouth' : '${s.tooth}',
                      style: TextStyle(
                        color: c.onAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _actions(CruColors c) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: (_controller == null || _capturing || _saving)
              ? null
              : _capture,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Capture'),
        ),
        const SizedBox(width: 12),
        Text(
          _tooth == null ? 'Full mouth' : 'Tooth $_tooth',
          style: TextStyle(color: c.label2),
        ),
        const Spacer(),
        if (_saving)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              'Saving $_saved of ${_shots.length}',
              style: TextStyle(color: c.label2),
            ),
          ),
        FilledButton(
          onPressed: (_shots.isEmpty || _saving) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _shots.isEmpty
                      ? 'Save to patient'
                      : 'Save ${_shots.length} to patient',
                ),
        ),
      ],
    );
  }
}

/// Compact FDI selector: upper and lower rows plus "full mouth".
class _ToothPicker extends StatelessWidget {
  const _ToothPicker({required this.selected, required this.onPick});

  final int? selected;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    Widget row(List<int> teeth) => Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final t in teeth)
          ChoiceChip(
            label: Text('$t', style: const TextStyle(fontSize: 12)),
            selected: selected == t,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
            onSelected: (_) => onPick(t),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoiceChip(
          label: const Text('No tooth / full mouth'),
          selected: selected == null,
          onSelected: (_) => onPick(null),
        ),
        const SizedBox(height: 6),
        row(_upperTeeth),
        const SizedBox(height: 6),
        row(_lowerTeeth),
      ],
    );
  }
}
