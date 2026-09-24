import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/dicom/dicom_file.dart';

const _rasterExt = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp', '.gif', '.webp'};

/// One file found for import.
class RadImportFile {
  const RadImportFile({
    required this.sourcePath,
    required this.kind,
    this.width = 0,
    this.height = 0,
    this.frames = 1,
    this.compressed = false,
    this.transferSyntax = '',
    this.seriesUid = '',
    this.seriesDescription = '',
    this.instanceNumber = 0,
    this.pixelSpacingMm,
    this.position,
    this.orientation,
    this.sliceThickness,
    this.sliceLocation,
    this.dicomModality = '',
  });

  final String sourcePath;
  final RadFileKind kind;
  final int width;
  final int height;
  final int frames;
  final bool compressed;
  final String transferSyntax;
  final String seriesUid;
  final String seriesDescription;
  final int instanceNumber;
  final double? pixelSpacingMm;
  final List<double>? position;
  final List<double>? orientation;
  final double? sliceThickness;
  final double? sliceLocation;
  final String dicomModality;

  RadImageRef toRef(String id, String storedPath) => RadImageRef(
        id: id,
        path: storedPath,
        kind: kind,
        seriesUid: seriesUid,
        seriesDescription: seriesDescription,
        instanceNumber: instanceNumber,
        width: width,
        height: height,
        frames: frames,
        compressed: compressed,
        transferSyntax: transferSyntax,
        pixelSpacingMm: pixelSpacingMm,
        position: position,
        orientation: orientation,
        sliceThickness: sliceThickness,
        sliceLocation: sliceLocation,
        dicomModality: dicomModality,
      );
}

/// The files of one study found in an import, with what the scans say
/// about the patient.
class RadImportGroup {
  RadImportGroup({
    required this.key,
    required this.files,
    this.patientName = '',
    this.patientExternalId = '',
    this.patientSex = '',
    this.patientDob,
    this.studyDate,
    this.modality = RadModality.other,
    this.description = '',
    this.institution = '',
    this.equipment = '',
    this.bodyPart = '',
    this.accession = '',
    this.studyUid = '',
    this.referringPhysician = '',
    this.dose = const RadDose(),
  });

  final String key;
  final List<RadImportFile> files;
  final String patientName;
  final String patientExternalId;
  final String patientSex;
  final DateTime? patientDob;
  final DateTime? studyDate;
  final RadModality modality;
  final String description;
  final String institution;
  final String equipment;
  final String bodyPart;
  final String accession;
  final String studyUid;
  final String referringPhysician;
  final RadDose dose;

  int get compressedCount => files.where((f) => f.compressed).length;
  bool get isDicom => files.any((f) => f.kind == RadFileKind.dicom);
  int get seriesCount => files.map((f) => f.seriesUid).toSet().length;
}

class RadImportScan {
  const RadImportScan({required this.groups, required this.skipped});

  final List<RadImportGroup> groups;

  /// Files that aren't images (reports, viewers on a patient CD…).
  final int skipped;

  bool get isEmpty => groups.isEmpty;
}

/// Finds images in files, folders (patient CDs with a DICOMDIR) and ZIP
/// files, and groups them by study. Runs off the UI thread.
Future<RadImportScan> scanForImport(List<String> paths, {required String tempDir}) =>
    Isolate.run(() => _scan(paths, tempDir));

RadImportScan _scan(List<String> paths, String tempDir) {
  final files = <File>[];
  var zipN = 0;
  void unzip(File zip) {
    final out = Directory(p.join(tempDir, 'zip_${zipN++}'))..createSync(recursive: true);
    try {
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final safe = p.normalize(f.name).replaceAll('..', '_');
        final target = File(p.join(out.path, safe));
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(f.content);
        files.add(target);
      }
    } catch (_) {}
  }

  void addFile(File f) {
    if (p.extension(f.path).toLowerCase() == '.zip') {
      unzip(f);
    } else {
      files.add(f);
    }
  }

  void add(String path) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      for (final e in Directory(path).listSync(recursive: true, followLinks: false)) {
        if (e is File) addFile(e);
      }
    } else if (type == FileSystemEntityType.file) {
      addFile(File(path));
    }
  }

  for (final path in paths) {
    add(path);
  }

  final byStudy = <String, List<(RadImportFile, DicomFile?)>>{};
  final raster = <RadImportFile>[];
  var skipped = 0;

  for (final f in files) {
    final name = p.basename(f.path).toUpperCase();
    if (name == 'DICOMDIR') continue;
    final ext = p.extension(f.path).toLowerCase();
    Uint8List bytes;
    try {
      bytes = f.readAsBytesSync();
    } catch (_) {
      skipped++;
      continue;
    }
    if (_rasterExt.contains(ext)) {
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (info == null) {
        skipped++;
        continue;
      }
      raster.add(RadImportFile(
        sourcePath: f.path,
        kind: RadFileKind.raster,
        width: info.width,
        height: info.height,
        seriesUid: 'pictures',
        seriesDescription: 'Pictures',
      ));
      continue;
    }
    if (!DicomFile.looksLikeDicom(bytes)) {
      skipped++;
      continue;
    }
    DicomFile d;
    try {
      d = DicomFile.parse(bytes);
    } catch (_) {
      skipped++;
      continue;
    }
    if (!d.hasPixels) {
      skipped++;
      continue;
    }
    final studyUid = d.string(DicomTag.studyInstanceUid) ??
        '${d.string(DicomTag.patientId) ?? ''}_${d.string(DicomTag.studyDate) ?? ''}';
    final pos = d.numbers(DicomTag.imagePosition);
    final ori = d.numbers(DicomTag.imageOrientation);
    (byStudy[studyUid] ??= []).add((
      RadImportFile(
        sourcePath: f.path,
        kind: RadFileKind.dicom,
        width: d.columns,
        height: d.rows,
        frames: d.frames,
        compressed: d.isCompressed,
        transferSyntax: d.transferSyntax,
        seriesUid: d.string(DicomTag.seriesInstanceUid) ?? 'series',
        seriesDescription: d.string(DicomTag.seriesDescription) ?? '',
        instanceNumber: d.integer(DicomTag.instanceNumber) ?? 0,
        pixelSpacingMm: d.pixelSpacingMm,
        position: pos != null && pos.length >= 3 ? pos.sublist(0, 3) : null,
        orientation: ori != null && ori.length >= 6 ? ori.sublist(0, 6) : null,
        sliceThickness: d.number(DicomTag.sliceThickness),
        sliceLocation: d.number(DicomTag.sliceLocation),
        dicomModality: d.string(DicomTag.modality) ?? '',
      ),
      byStudy[studyUid]?.isEmpty ?? true ? d : null,
    ));
  }

  final groups = <RadImportGroup>[];
  for (final e in byStudy.entries) {
    final list = e.value;
    final header = list.firstWhere((x) => x.$2 != null, orElse: () => list.first).$2;
    final files = list.map((x) => x.$1).toList()
      ..sort((a, b) => a.seriesUid != b.seriesUid
          ? a.seriesUid.compareTo(b.seriesUid)
          : a.instanceNumber.compareTo(b.instanceNumber));
    groups.add(_groupFrom(e.key, files, header));
  }
  if (raster.isNotEmpty) {
    raster.sort((a, b) => a.sourcePath.compareTo(b.sourcePath));
    groups.add(RadImportGroup(
      key: 'pictures',
      files: raster,
      modality: guessRasterModality(raster.first),
    ));
  }
  return RadImportScan(groups: groups, skipped: skipped);
}

RadImportGroup _groupFrom(String key, List<RadImportFile> files, DicomFile? d) {
  if (d == null) return RadImportGroup(key: key, files: files);
  final manufacturer = d.string(DicomTag.manufacturer) ?? '';
  final model = d.string(DicomTag.modelName) ?? '';
  final exposureMs = d.number(DicomTag.exposureTime);
  final ma = d.number(DicomTag.tubeCurrent);
  return RadImportGroup(
    key: key,
    files: files,
    patientName: d.personName(DicomTag.patientName) ?? '',
    patientExternalId: d.string(DicomTag.patientId) ?? '',
    patientSex: switch (d.string(DicomTag.sex)) {
      'M' => 'Male',
      'F' => 'Female',
      'O' => 'Other',
      _ => '',
    },
    patientDob: d.date(DicomTag.birthDate),
    studyDate: d.date(DicomTag.studyDate, DicomTag.studyTime) ??
        d.date(DicomTag.seriesDate) ??
        d.date(DicomTag.acquisitionDate),
    modality: guessDicomModality(d, files),
    description: d.string(DicomTag.studyDescription) ?? d.string(DicomTag.seriesDescription) ?? '',
    institution: d.string(DicomTag.institution) ?? '',
    equipment: [manufacturer, model].where((s) => s.isNotEmpty).join(' '),
    bodyPart: d.string(DicomTag.bodyPart) ?? '',
    accession: d.string(DicomTag.accession) ?? '',
    studyUid: d.string(DicomTag.studyInstanceUid) ?? '',
    referringPhysician: d.personName(DicomTag.referringPhysician) ?? '',
    dose: RadDose(
      kvp: d.number(DicomTag.kvp),
      ma: ma,
      exposureMs: exposureMs,
      mas: d.number(DicomTag.exposure) ??
          (ma != null && exposureMs != null ? ma * exposureMs / 1000 : null),
      dap: d.number(DicomTag.dap),
    ),
  );
}

/// The study type from the DICOM modality, descriptions and shape.
RadModality guessDicomModality(DicomFile d, List<RadImportFile> files) {
  final mod = (d.string(DicomTag.modality) ?? '').toUpperCase();
  final text = [
    d.string(DicomTag.studyDescription),
    d.string(DicomTag.seriesDescription),
    d.string(DicomTag.bodyPart),
  ].whereType<String>().join(' ').toLowerCase();
  final slices = files.fold<int>(0, (n, f) => n + f.frames);
  if (mod == 'CT' || slices > 20) return RadModality.cbct;
  if (text.contains('ceph')) return RadModality.ceph;
  if (text.contains('tmj')) return RadModality.tmj;
  if (mod == 'PX' || text.contains('pan') || text.contains('opg') || text.contains('ortho')) {
    return RadModality.opg;
  }
  if (text.contains('bite') || text.contains('bw')) return RadModality.bitewing;
  if (text.contains('occlus')) return RadModality.occlusal;
  if (mod == 'IO' || text.contains('periap')) return RadModality.iopa;
  if (mod == 'XC' || mod == 'VL' || mod == 'OP') return RadModality.photo;
  final f = files.first;
  if (f.height > 0 && f.width / f.height > 1.7) return RadModality.opg;
  return RadModality.other;
}

/// The study type of a picture from its file name and shape.
RadModality guessRasterModality(RadImportFile f) {
  final name = p.basename(f.sourcePath).toLowerCase();
  if (name.contains('cbct')) return RadModality.cbct;
  if (name.contains('ceph')) return RadModality.ceph;
  if (name.contains('tmj')) return RadModality.tmj;
  if (name.contains('opg') || name.contains('pano')) return RadModality.opg;
  if (name.contains('bite') || name.contains('bw')) return RadModality.bitewing;
  if (name.contains('occl')) return RadModality.occlusal;
  if (name.contains('iopa') || name.contains('pa_') || name.contains('periap')) {
    return RadModality.iopa;
  }
  if (f.height > 0 && f.width / f.height > 1.7) return RadModality.opg;
  if (f.width < 2200 && f.height < 2200) return RadModality.iopa;
  return RadModality.other;
}

/// Copies [group]'s files into [studyDir] and returns their references
/// (in the order given). Runs off the UI thread.
Future<List<RadImageRef>> copyIntoStudy(RadImportGroup group, String studyDir) {
  final files = group.files;
  return Isolate.run(() {
    Directory(studyDir).createSync(recursive: true);
    final refs = <RadImageRef>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final ext = f.kind == RadFileKind.dicom ? '.dcm' : p.extension(f.sourcePath).toLowerCase();
      final stored = 'img_${i.toString().padLeft(4, '0')}$ext';
      File(f.sourcePath).copySync(p.join(studyDir, stored));
      refs.add(f.toRef('img_$i', stored));
    }
    return refs;
  });
}
