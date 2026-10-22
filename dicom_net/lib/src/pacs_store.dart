import 'dart:io';
import 'dart:typed_data';

import 'dataset.dart';

/// One stored file and the attributes a PACS searches on.
class StoredInstance {
  StoredInstance({
    required this.path,
    required this.size,
    required this.attrs,
    required this.transferSyntax,
    this.source = '',
  });

  final String path;
  final int size;
  final Map<DicomAttr, String> attrs;
  final String transferSyntax;

  /// How it arrived: "sample", "import", "STOW from 192.168.1.5".
  final String source;

  String operator [](DicomAttr a) => attrs[a] ?? '';

  String get studyUid => this[DicomAttr.studyInstanceUid];
  String get seriesUid => this[DicomAttr.seriesInstanceUid];
  String get sopUid => this[DicomAttr.sopInstanceUid];

  static const indexed = [
    DicomAttr.patientName,
    DicomAttr.patientId,
    DicomAttr.patientBirthDate,
    DicomAttr.patientSex,
    DicomAttr.studyInstanceUid,
    DicomAttr.studyDate,
    DicomAttr.studyTime,
    DicomAttr.accessionNumber,
    DicomAttr.studyDescription,
    DicomAttr.referringPhysicianName,
    DicomAttr.studyId,
    DicomAttr.seriesInstanceUid,
    DicomAttr.seriesNumber,
    DicomAttr.seriesDescription,
    DicomAttr.modality,
    DicomAttr.sopClassUid,
    DicomAttr.sopInstanceUid,
    DicomAttr.instanceNumber,
    DicomAttr.rows,
    DicomAttr.columns,
    DicomAttr.numberOfFrames,
    DicomAttr.bodyPartExamined,
  ];

  static StoredInstance fromInstance(
    DicomInstance d,
    String path, {
    String source = '',
  }) {
    final attrs = <DicomAttr, String>{};
    for (final a in indexed) {
      final v = a.vr == 'US' ? d.integer(a)?.toString() : d.string(a);
      if (v != null) attrs[a] = v;
    }
    attrs[DicomAttr.sopClassUid] = d.sopClassUid;
    attrs[DicomAttr.sopInstanceUid] = d.sopInstanceUid;
    return StoredInstance(
      path: path,
      size: d.bytes.length,
      attrs: attrs,
      transferSyntax: d.transferSyntax,
      source: source,
    );
  }
}

/// A PACS archive in a folder of .dcm files, indexed in memory.
class FolderPacsStore {
  FolderPacsStore(this.dir);

  final Directory dir;
  final List<StoredInstance> instances = [];
  final _sources = <String, String>{};

  File get _sourceFile => File('${dir.path}${Platform.pathSeparator}.sources');

  /// Reads every file in the folder.
  Future<void> load() async {
    await dir.create(recursive: true);
    instances.clear();
    if (await _sourceFile.exists()) {
      for (final line in await _sourceFile.readAsLines()) {
        final i = line.indexOf('\t');
        if (i > 0) _sources[line.substring(0, i)] = line.substring(i + 1);
      }
    }
    await for (final e in dir.list()) {
      if (e is! File || !e.path.toLowerCase().endsWith('.dcm')) continue;
      try {
        final d = DicomInstance.parse(await e.readAsBytes());
        instances.add(
          StoredInstance.fromInstance(
            d,
            e.path,
            source: _sources[d.sopInstanceUid] ?? '',
          ),
        );
      } catch (_) {
        // Not readable: left in the folder, not served.
      }
    }
  }

  /// Stores a Part 10 file, replacing one with the same SOP Instance UID.
  Future<StoredInstance> add(Uint8List bytes, {String source = ''}) async {
    final d = DicomInstance.parse(bytes);
    if (d.sopInstanceUid.isEmpty) {
      throw DicomFormatException('No SOP Instance UID');
    }
    final safe = d.sopInstanceUid.replaceAll(RegExp(r'[^0-9.]'), '_');
    final path = '${dir.path}${Platform.pathSeparator}$safe.dcm';
    await File(path).writeAsBytes(bytes, flush: true);
    instances.removeWhere((i) => i.sopUid == d.sopInstanceUid);
    final inst = StoredInstance.fromInstance(d, path, source: source);
    instances.add(inst);
    if (source.isNotEmpty) {
      _sources[d.sopInstanceUid] = source;
      await _sourceFile.writeAsString(
        '${d.sopInstanceUid}\t$source\n',
        mode: FileMode.append,
      );
    }
    return inst;
  }

  Future<Uint8List> read(StoredInstance i) => File(i.path).readAsBytes();

  Future<void> deleteStudy(String studyUid) async {
    for (final i in instances.where((i) => i.studyUid == studyUid).toList()) {
      try {
        await File(i.path).delete();
      } catch (_) {}
      instances.remove(i);
    }
  }

  /// Instances grouped by study, newest study date first.
  Map<String, List<StoredInstance>> byStudy() {
    final m = <String, List<StoredInstance>>{};
    for (final i in instances) {
      (m[i.studyUid] ??= []).add(i);
    }
    final keys = m.keys.toList()
      ..sort(
        (a, b) => (m[b]!.first[DicomAttr.studyDate]).compareTo(
          m[a]!.first[DicomAttr.studyDate],
        ),
      );
    return {for (final k in keys) k: m[k]!};
  }
}
