import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/therapy/data/exercise_library.dart';
import 'package:doctor_management_app/features/therapy/domain/hep_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// The visual area of an exercise: the physio's own photo if attached, else
/// the region icon, with play / link buttons for a video. When [editable] the
/// physio can attach a photo, a video or a link. Bundled illustrations can
/// later drop in here without touching the screens that use it.
class ExerciseVisual extends ConsumerWidget {
  const ExerciseVisual({
    super.key,
    required this.exercise,
    this.editable = false,
    this.height = 180,
  });

  final ExerciseDef exercise;
  final bool editable;
  final double height;

  Future<String?> _pick(BuildContext context, {required bool video}) async {
    if (_isMobile) {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(video ? 'Record a video' : 'Take a photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return null;
      final picker = ImagePicker();
      final f = video
          ? await picker.pickVideo(source: source)
          : await picker.pickImage(source: source, imageQuality: 85);
      return f?.path;
    }
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: video
          ? ['mp4', 'mov', 'm4v', 'webm']
          : ['jpg', 'jpeg', 'png', 'webp'],
    );
    return r?.files.single.path;
  }

  Future<void> _attach(BuildContext context, WidgetRef ref, String kind) async {
    final path = await _pick(context, video: kind == 'video');
    if (path == null) return;
    try {
      await attachExerciseFile(ref, exercise, kind, path);
    } catch (e) {
      debugPrint('attach exercise media failed: $e');
      if (context.mounted) recToast(context, "Couldn't save that. Try again.");
    }
  }

  Future<void> _editLink(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: exercise.videoLink ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Video link',
        subtitle: exercise.name,
        width: 420,
        submitLabel: 'Save',
        onSubmit: () => Navigator.of(ctx).pop(true),
        body: CruTextField(
          label: 'Link (YouTube etc.)',
          controller: ctrl,
          hint: 'https://',
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
      ),
    );
    if (ok == true) await setExerciseLink(ref, exercise, ctrl.text);
  }

  Future<void> _playLocal(BuildContext context, String path) async {
    if (_isMobile) {
      await showDialog<void>(
        context: context,
        builder: (_) => _VideoDialog(path: path),
      );
    } else {
      await launchUrl(Uri.file(path));
    }
  }

  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link.startsWith('http') ? link : 'https://$link');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final photo = exercise.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();
    final video = exercise.videoPath;
    final link = exercise.videoLink;

    Widget capsule(String label, VoidCallback onTap) =>
        CruCapsuleButton(label: label, onPressed: onTap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: c.inset,
            borderRadius: BorderRadius.circular(CruRadius.control),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasPhoto
              ? Image.file(File(photo), fit: BoxFit.cover)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(exercise.region.icon, size: 44, color: c.label3),
                    const SizedBox(height: CruSpace.s8),
                    Text(
                      editable
                          ? 'Add your own photo or video'
                          : exercise.region.label,
                      style: CruType.caption.tint(c.label3),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: CruSpace.s8),
        Wrap(
          spacing: CruSpace.s8,
          runSpacing: CruSpace.s8,
          children: [
            if (video != null)
              capsule('Play video', () => _playLocal(context, video)),
            if (link != null) capsule('Open link', () => _openLink(link)),
            if (editable) ...[
              capsule(
                hasPhoto ? 'Replace photo' : 'Add photo',
                () => _attach(context, ref, 'photo'),
              ),
              capsule(
                video != null ? 'Replace video' : 'Add video',
                () => _attach(context, ref, 'video'),
              ),
              capsule(
                link != null ? 'Edit link' : 'Add link',
                () => _editLink(context, ref),
              ),
              if (hasPhoto)
                capsule(
                  'Remove photo',
                  () => removeExerciseFile(ref, exercise, 'photo'),
                ),
              if (video != null)
                capsule(
                  'Remove video',
                  () => removeExerciseFile(ref, exercise, 'video'),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

class _VideoDialog extends StatefulWidget {
  const _VideoDialog({required this.path});
  final String path;

  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  late final VideoPlayerController _c = VideoPlayerController.file(
    File(widget.path),
  );
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c
        ..setLooping(true)
        ..play();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(CruSpace.s16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_ready)
            GestureDetector(
              onTap: () =>
                  setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
              child: AspectRatio(
                aspectRatio: _c.value.aspectRatio,
                child: VideoPlayer(_c),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(CruSpace.s32),
              child: CircularProgressIndicator(),
            ),
          Positioned(
            top: CruSpace.s4,
            right: CruSpace.s4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
