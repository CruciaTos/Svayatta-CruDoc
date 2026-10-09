import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dashboard/presentation/dashboard_actions.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/add_files_dialog.dart';
import 'package:doctor_management_app/features/files/presentation/file_viewer.dart';
import 'package:doctor_management_app/features/files/presentation/files_dialogs.dart';
import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/mobile/mobile_more.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/radiology/open_dicom_file.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the Files screen and the patient's Files card can do. Dialogs open
/// from the root navigator, like the other screens' actions.
abstract final class FilesActions {
  static BuildContext _root(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).context;

  static void say(BuildContext context, String text) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );

  static Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on FilesException catch (e) {
      if (context.mounted) say(context, e.message);
    } catch (e) {
      debugPrint('[Files] $e');
      if (context.mounted) say(context, 'That didn’t work. Try again.');
    }
  }

  // ───────────────────────────── Opening ─────────────────────────────

  /// Opens a file straight away: pictures and PDFs inside CruDoc, DICOM in
  /// CruDoc's X-ray viewer, anything else in the computer's own app. Downloads it first when this device
  /// doesn't have it yet.
  static Future<void> open(
    BuildContext context,
    PatientFile file, {
    required String patientName,
  }) async {
    // A double tap reaches here twice; the second must not open it again.
    if (_opening) return;
    _opening = true;
    try {
      await _open(context, file, patientName: patientName);
    } finally {
      _opening = false;
    }
  }

  static bool _opening = false;

  static Future<void> _open(
    BuildContext context,
    PatientFile file, {
    required String patientName,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    if (file.localPath.isEmpty && file.storagePath.isNotEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Downloading ${file.name}…'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    try {
      final local = await FilesRepository.instance.localCopy(file);
      messenger?.hideCurrentSnackBar();
      // DICOM opens in CruDoc's own X-ray viewer, not another app.
      if (file.contentType == PatientFileTypes.dicom &&
          !kIsWeb &&
          context.mounted) {
        final shown = await openDicomFileInViewer(
          context,
          file: file,
          local: local,
          patientName: patientName,
        );
        if (shown) return;
      }
      final inApp =
          PatientFileTypes.isViewableImage(file.contentType) ||
          file.contentType == 'application/pdf';
      if (inApp) {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => FileViewerPage(
              file: file,
              local: local,
              patientName: patientName,
            ),
          ),
        );
        return;
      }
      final opened = await launchUrl(Uri.file(local.path));
      if (!opened) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              filesOnDesktop
                  ? 'No app on this computer opens ${file.name}.'
                  : 'Open ${file.name} on the clinic computer.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FilesException catch (e) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      debugPrint('[Files] opening ${file.id}: $e');
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text("Couldn't open ${file.name}."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Opens the file's patient.
  static void openPatient(BuildContext context, WidgetRef ref, String id) {
    final patients = ref.read(patientsStreamProvider).value ?? const [];
    for (final p in patients) {
      if (p.id == id) {
        DashboardActions.openPatient(context, p);
        return;
      }
    }
    say(context, "This patient isn't in your patient list.");
  }

  /// The Files screen limited to one patient ("See all").
  static void showForPatient(
    BuildContext context,
    WidgetRef ref,
    String patientId,
  ) {
    ref.read(filesControllerProvider.notifier).showPatient(patientId);
    final navigate = ref.read(shellNavigatorProvider);
    if (navigate != null && navigate(DesktopTab.files)) return;
    openMobileDestination(context, DesktopTab.files);
  }

  // ───────────────────────────── Adding ─────────────────────────────

  /// Chooses files from the computer or phone, then asks who they're for.
  static Future<void> pickAndAdd(
    BuildContext context, {
    String? patientId,
    String folderId = '',
  }) async {
    // On a phone the doctor often photographs a paper report there and then.
    if (_onPhone) {
      final camera = await _askTakePhoto(context);
      if (camera == null || !context.mounted) return;
      if (camera) {
        await _takePhotoAndAdd(
          context,
          patientId: patientId,
          folderId: folderId,
        );
        return;
      }
    }
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;
    final sources = [
      for (final f in result.files)
        FileSource(
          name: f.name,
          sizeBytes: f.size,
          path: kIsWeb ? null : f.path,
          bytes: f.bytes,
        ),
    ];
    await addSources(
      context,
      sources,
      patientId: patientId,
      folderId: folderId,
    );
  }

  static bool get _onPhone =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// True for the camera, false for files, null when dismissed.
  static Future<bool?> _askTakePhoto(BuildContext context) =>
      showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CruSpace.s8,
              0,
              CruSpace.s8,
              CruSpace.s16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.pop(sheet, true),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Choose files'),
                  onTap: () => Navigator.pop(sheet, false),
                ),
              ],
            ),
          ),
        ),
      );

  static Future<void> _takePhotoAndAdd(
    BuildContext context, {
    String? patientId,
    String folderId = '',
  }) async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('[Files] camera: $e');
      if (context.mounted) say(context, 'The camera couldn’t be opened.');
      return;
    }
    if (photo == null) return;
    final size = await File(photo.path).length();
    if (!context.mounted) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final dot = photo.path.lastIndexOf('.');
    final ext = dot >= 0 ? photo.path.substring(dot) : '.jpg';
    final name =
        'Photo ${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}.${two(now.minute)}.${two(now.second)}$ext';
    await addSources(
      context,
      [FileSource(name: name, sizeBytes: size, path: photo.path)],
      patientId: patientId,
      folderId: folderId,
    );
  }

  /// Files dropped on the screen.
  static Future<void> addPaths(
    BuildContext context,
    List<String> paths, {
    String? patientId,
    String folderId = '',
  }) async {
    final sources = [
      for (final path in paths) ?await FileSource.fromPath(path),
    ];
    if (sources.isEmpty) {
      if (context.mounted) {
        say(context, 'Folders can’t be dropped. Drop the files inside them.');
      }
      return;
    }
    if (!context.mounted) return;
    await addSources(
      context,
      sources,
      patientId: patientId,
      folderId: folderId,
    );
  }

  static Future<void> addSources(
    BuildContext context,
    List<FileSource> sources, {
    String? patientId,
    String folderId = '',
  }) async {
    final added = await showAddFilesDialog(
      _root(context),
      sources: sources,
      patientId: patientId,
      folderId: folderId,
    );
    if (added != null && added > 0 && context.mounted) {
      say(context, added == 1 ? 'File added.' : '$added files added.');
    }
  }

  // ───────────────────────────── Folders ─────────────────────────────

  static Future<void> newFolder(
    BuildContext context, {
    String parentId = '',
  }) async {
    final name = await showFilesNameDialog(
      _root(context),
      title: 'New folder',
      submitLabel: 'Create folder',
    );
    if (name == null || !context.mounted) return;
    await _guard(
      context,
      () => FilesRepository.instance.createFolder(name, parentId: parentId),
    );
  }

  static Future<void> renameFolder(
    BuildContext context,
    FolderEntry entry,
  ) async {
    final name = await showFilesNameDialog(
      _root(context),
      title: 'Rename folder',
      submitLabel: 'Rename',
      initial: entry.folder.name,
    );
    if (name == null || !context.mounted) return;
    await _guard(
      context,
      () => FilesRepository.instance.renameFolder(entry.id, name),
    );
  }

  static Future<void> moveFolder(
    BuildContext context,
    WidgetRef ref,
    FolderEntry entry,
  ) async {
    final folders = ref.read(filesViewProvider).value?.allFolders ?? const [];
    final target = await showMoveToFolderDialog(
      _root(context),
      folders: folders,
      currentFolderId: entry.folder.parentId,
      title: 'Move “${entry.folder.name}”',
      exclude: entry.id,
    );
    if (target == null || !context.mounted) return;
    await _guard(
      context,
      () => FilesRepository.instance.moveFolder(entry.id, target),
    );
  }

  static Future<void> shareFolder(BuildContext context, FolderEntry entry) =>
      showShareFolderDialog(_root(context), folder: entry.folder);

  static Future<void> deleteFolder(
    BuildContext context,
    WidgetRef ref,
    FolderEntry entry,
  ) async {
    final contents = await FilesRepository.instance.folderContents(entry.id);
    if (!context.mounted) return;
    final parts = [
      if (contents.folders > 0)
        contents.folders == 1 ? '1 folder' : '${contents.folders} folders',
      if (contents.files > 0)
        contents.files == 1 ? '1 file' : '${contents.files} files',
    ];
    final ok = await confirmFilesDelete(
      _root(context),
      title: 'Delete “${entry.folder.name}”?',
      body: parts.isEmpty
          ? 'The folder is empty.'
          : 'The ${parts.join(' and ')} inside it will be deleted too, for '
                'everyone it is shared with.',
    );
    if (!ok || !context.mounted) return;
    final controller = ref.read(filesControllerProvider.notifier);
    final open = ref.read(filesControllerProvider).folderId;
    await _guard(context, () async {
      await FilesRepository.instance.deleteFolder(entry.id);
      if (open == entry.id) controller.openFolder(entry.folder.parentId);
    });
  }

  // ───────────────────────────── Files ─────────────────────────────

  static Future<void> renameFile(BuildContext context, FileEntry entry) async {
    final name = await showFilesNameDialog(
      _root(context),
      title: 'Rename file',
      submitLabel: 'Rename',
      initial: entry.file.name,
      icon: CruIcons.fileText,
    );
    if (name == null || !context.mounted) return;
    await _guard(
      context,
      () => FilesRepository.instance.renameFile(entry.id, name),
    );
  }

  static Future<void> moveFile(
    BuildContext context,
    WidgetRef ref,
    FileEntry entry,
  ) async {
    final folders = ref.read(filesViewProvider).value?.allFolders ?? const [];
    final target = await showMoveToFolderDialog(
      _root(context),
      folders: folders,
      currentFolderId: entry.file.folderId,
      title: 'Move “${entry.file.name}”',
    );
    if (target == null || !context.mounted) return;
    await _guard(
      context,
      () => FilesRepository.instance.moveFiles([entry.id], target),
    );
  }

  /// Drag and drop onto a folder.
  static Future<void> dropOnFolder(
    BuildContext context,
    FileEntry entry,
    String folderId,
  ) async {
    if (!entry.canManage) {
      say(context, 'Only the person who added this file can move it.');
      return;
    }
    await _guard(
      context,
      () => FilesRepository.instance.moveFiles([entry.id], folderId),
    );
  }

  static Future<void> changePatient(
    BuildContext context,
    FileEntry entry,
  ) async {
    final p = await showPatientPickerDialog(
      _root(context),
      title: 'Who is “${entry.file.name}” for?',
    );
    if (p == null || !context.mounted) return;
    await _guard(
      context,
      () => FilesRepository.instance.changePatient(entry.id, p.id),
    );
  }

  static Future<void> deleteFile(BuildContext context, FileEntry entry) async {
    final ok = await confirmFilesDelete(
      _root(context),
      title: 'Delete “${entry.file.name}”?',
      body: entry.file.visibleTo.length > 1
          ? 'It will be gone for everyone it is shared with.'
          : 'It will be gone from every device.',
    );
    if (!ok || !context.mounted) return;
    await _guard(context, () => FilesRepository.instance.deleteFile(entry.id));
  }
}
