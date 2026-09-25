// Oral & Maxillofacial Radiology records. Every record is a plain JSON
// document in the `radiology_docs` table (see RadiologyRepository), so a
// new field only needs a default here, never a migration.

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
    raw is List ? [for (final e in raw) if (e is Map) f(Map<String, dynamic>.from(e))] : <T>[];

List<String> _strings(Object? raw) =>
    raw is List ? [for (final e in raw) '$e'] : <String>[];

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

DateTime? _date(Object? raw) =>
    raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;

double? _double(Object? raw) => raw is num ? raw.toDouble() : null;

String _str(Object? raw) => raw is String ? raw : '';

// ───────────────────────────── Enums ─────────────────────────────

/// What kind of scan a study is. Picks the viewer (CBCT opens the 3D
/// viewer), the report template and the fee.
enum RadModality {
  cbct('CBCT', 'Cone-beam CT'),
  opg('OPG', 'Panoramic (OPG)'),
  ceph('Ceph', 'Lateral ceph'),
  iopa('IOPA', 'Periapical (IOPA)'),
  bitewing('Bitewing', 'Bitewing'),
  occlusal('Occlusal', 'Occlusal'),
  tmj('TMJ', 'TMJ series'),
  photo('Photo', 'Clinical photo'),
  other('Other', 'Other');

  const RadModality(this.short, this.label);

  /// "CBCT", "OPG".
  final String short;

  /// "Cone-beam CT", "Panoramic (OPG)".
  final String label;

  bool get isVolume => this == cbct;

  static RadModality fromName(Object? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => other);
}

/// How soon the referrer needs the report.
enum RadPriority {
  routine('Routine'),
  urgent('Urgent'),
  stat('STAT');

  const RadPriority(this.label);
  final String label;

  static RadPriority fromName(Object? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => routine);
}

/// Where a study is in the reading workflow. The report moves it along.
enum RadStudyStatus {
  newStudy('New'),
  reading('Reading'),
  draft('Draft'),
  preliminary('Preliminary'),
  finalised('Final'),
  delivered('Sent');

  const RadStudyStatus(this.label);
  final String label;

  /// Still needs the radiologist (not signed yet).
  bool get isOpen => index < finalised.index;

  static RadStudyStatus fromName(Object? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => newStudy);
}

enum RadFileKind {
  /// A DICOM file (uncompressed pixel data can be shown).
  dicom,

  /// A plain picture: JPG, PNG, TIFF, BMP.
  raster;

  static RadFileKind fromName(Object? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => raster);
}

// ───────────────────────────── Study ─────────────────────────────

/// One image file stored in a study's folder.
class RadImageRef {
  const RadImageRef({
    required this.id,
    required this.path,
    required this.kind,
    this.seriesUid = '',
    this.seriesDescription = '',
    this.instanceNumber = 0,
    this.width = 0,
    this.height = 0,
    this.frames = 1,
    this.compressed = false,
    this.transferSyntax = '',
    this.pixelSpacingMm,
    this.position,
    this.orientation,
    this.sliceThickness,
    this.sliceLocation,
    this.dicomModality = '',
  });

  final String id;

  /// File name relative to the study folder.
  final String path;
  final RadFileKind kind;
  final String seriesUid;
  final String seriesDescription;
  final int instanceNumber;
  final int width;
  final int height;
  final int frames;

  /// Compressed DICOM pixel data (JPEG 2000, JPEG-LS…): not shown yet.
  final bool compressed;
  final String transferSyntax;

  /// Millimetres per pixel from the file, when it says.
  final double? pixelSpacingMm;

  /// DICOM Image Position (Patient), x y z in mm.
  final List<double>? position;

  /// DICOM Image Orientation (Patient), row and column direction cosines.
  final List<double>? orientation;
  final double? sliceThickness;
  final double? sliceLocation;

  /// The DICOM Modality tag ("CT", "PX", "IO", "DX"…).
  final String dicomModality;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'kind': kind.name,
        'seriesUid': seriesUid,
        'seriesDescription': seriesDescription,
        'instanceNumber': instanceNumber,
        'width': width,
        'height': height,
        'frames': frames,
        'compressed': compressed,
        'transferSyntax': transferSyntax,
        'pixelSpacingMm': pixelSpacingMm,
        'position': position,
        'orientation': orientation,
        'sliceThickness': sliceThickness,
        'sliceLocation': sliceLocation,
        'dicomModality': dicomModality,
      };

  factory RadImageRef.fromJson(Map<String, dynamic> j) => RadImageRef(
        id: _str(j['id']),
        path: _str(j['path']),
        kind: RadFileKind.fromName(j['kind']),
        seriesUid: _str(j['seriesUid']),
        seriesDescription: _str(j['seriesDescription']),
        instanceNumber: (j['instanceNumber'] as num?)?.toInt() ?? 0,
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        frames: (j['frames'] as num?)?.toInt() ?? 1,
        compressed: j['compressed'] == true,
        transferSyntax: _str(j['transferSyntax']),
        pixelSpacingMm: _double(j['pixelSpacingMm']),
        position: (j['position'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        orientation:
            (j['orientation'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        sliceThickness: _double(j['sliceThickness']),
        sliceLocation: _double(j['sliceLocation']),
        dicomModality: _str(j['dicomModality']),
      );
}

/// Exposure values read from the DICOM file (radiation dose log).
class RadDose {
  const RadDose({this.kvp, this.ma, this.exposureMs, this.mas, this.dap});

  final double? kvp;
  final double? ma;
  final double? exposureMs;
  final double? mas;

  /// Dose-area product in the unit the file used (usually dGy·cm²).
  final double? dap;

  bool get isEmpty =>
      kvp == null && ma == null && exposureMs == null && mas == null && dap == null;

  Map<String, dynamic> toJson() =>
      {'kvp': kvp, 'ma': ma, 'exposureMs': exposureMs, 'mas': mas, 'dap': dap};

  factory RadDose.fromJson(Map<String, dynamic> j) => RadDose(
        kvp: _double(j['kvp']),
        ma: _double(j['ma']),
        exposureMs: _double(j['exposureMs']),
        mas: _double(j['mas']),
        dap: _double(j['dap']),
      );
}

/// A point in image pixels.
class RadPoint {
  const RadPoint(this.x, this.y);
  final double x;
  final double y;

  List<double> toJson() => [x, y];
  factory RadPoint.fromJson(Object? j) {
    final l = j is List ? j : const [0, 0];
    return RadPoint((l[0] as num).toDouble(), (l[1] as num).toDouble());
  }
}

enum RadAnnoKind {
  length,
  angle,
  polygon,
  ellipse,
  rect,
  polyline,
  arrow,
  text,
  freehand,
  toothLabel;

  bool get isMeasurement =>
      this == length || this == angle || this == polygon || this == ellipse ||
      this == rect || this == polyline;

  static RadAnnoKind fromName(Object? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => arrow);
}

/// A measurement or annotation drawn on one image (or one CBCT view).
class RadAnnotation {
  const RadAnnotation({
    required this.id,
    required this.kind,
    required this.points,
    this.text = '',
    this.colorHex = '',
  });

  final String id;
  final RadAnnoKind kind;

  /// In image pixels.
  final List<RadPoint> points;

  /// Label, note, or tooth number.
  final String text;

  /// "#RRGGBB", empty for the default colour.
  final String colorHex;

  RadAnnotation copyWith({List<RadPoint>? points, String? text, String? colorHex}) =>
      RadAnnotation(
        id: id,
        kind: kind,
        points: points ?? this.points,
        text: text ?? this.text,
        colorHex: colorHex ?? this.colorHex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'points': [for (final p in points) p.toJson()],
        'text': text,
        'colorHex': colorHex,
      };

  factory RadAnnotation.fromJson(Map<String, dynamic> j) => RadAnnotation(
        id: _str(j['id']),
        kind: RadAnnoKind.fromName(j['kind']),
        points: [for (final p in (j['points'] as List? ?? const [])) RadPoint.fromJson(p)],
        text: _str(j['text']),
        colorHex: _str(j['colorHex']),
      );
}

/// A view the radiologist marked for the report. The viewer saves a PNG
/// of it (annotations burned in) in the study folder.
class RadKeyImage {
  const RadKeyImage({
    required this.id,
    required this.imageId,
    required this.pngPath,
    this.caption = '',
    required this.createdAt,
  });

  final String id;

  /// The image (or CBCT view name) it came from.
  final String imageId;

  /// PNG file name relative to the study folder.
  final String pngPath;
  final String caption;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageId': imageId,
        'pngPath': pngPath,
        'caption': caption,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory RadKeyImage.fromJson(Map<String, dynamic> j) => RadKeyImage(
        id: _str(j['id']),
        imageId: _str(j['imageId']),
        pngPath: _str(j['pngPath']),
        caption: _str(j['caption']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
      );
}

/// A logged phone call or message about a critical finding.
class RadCriticalLog {
  const RadCriticalLog({required this.at, required this.note, this.contacted = ''});

  final DateTime at;

  /// Who was told ("Dr. Shah, by phone").
  final String contacted;
  final String note;

  Map<String, dynamic> toJson() =>
      {'at': at.millisecondsSinceEpoch, 'contacted': contacted, 'note': note};

  factory RadCriticalLog.fromJson(Map<String, dynamic> j) => RadCriticalLog(
        at: _date(j['at']) ?? DateTime.now(),
        contacted: _str(j['contacted']),
        note: _str(j['note']),
      );
}

/// One imaging study: the scans for one referral, its referral details
/// and where it is in the reading workflow.
class RadStudy {
  const RadStudy({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.patientSex = '',
    this.patientDob,
    this.patientExternalId = '',
    required this.modality,
    required this.studyDate,
    required this.receivedAt,
    this.description = '',
    this.referrerId = '',
    this.clinicalQuestion = '',
    this.priority = RadPriority.routine,
    this.status = RadStudyStatus.newStudy,
    this.dueAt,
    this.images = const [],
    this.dose = const RadDose(),
    this.studyUid = '',
    this.accession = '',
    this.institution = '',
    this.equipment = '',
    this.bodyPart = '',
    this.annotations = const {},
    this.calibration = const {},
    this.keyImages = const [],
    this.critical = false,
    this.criticalLog = const [],
    this.fee,
    this.invoiced = false,
    this.extras = const {},
    this.aiReads = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// CruDoc patient id (empty until matched or created).
  final String patientId;

  /// Name as the scan or referral gave it.
  final String patientName;
  final String patientSex;
  final DateTime? patientDob;

  /// Patient ID from the scanner (DICOM PatientID).
  final String patientExternalId;
  final RadModality modality;
  final DateTime studyDate;
  final DateTime receivedAt;
  final String description;
  final String referrerId;

  /// Why the scan was taken ("Implant site 36", "Swelling left mandible").
  final String clinicalQuestion;
  final RadPriority priority;
  final RadStudyStatus status;

  /// When the report is due (from the priority's turnaround time).
  final DateTime? dueAt;
  final List<RadImageRef> images;
  final RadDose dose;
  final String studyUid;
  final String accession;
  final String institution;

  /// "Planmeca ProMax 3D" (manufacturer and model).
  final String equipment;
  final String bodyPart;

  /// Annotations by image id (or CBCT view key).
  final Map<String, List<RadAnnotation>> annotations;

  /// Millimetres per pixel set with the ruler, by image id.
  final Map<String, double> calibration;
  final List<RadKeyImage> keyImages;

  /// A critical finding was flagged (the referrer must be told).
  final bool critical;
  final List<RadCriticalLog> criticalLog;

  /// Fee charged for reading this study (from the fee list by default).
  final double? fee;
  final bool invoiced;

  /// Module data by key: 'ceph' (landmarks per image), 'cbct' (arch
  /// curve, canals, implants, 3D presets), 'subtraction'. Each module owns
  /// its key.
  final Map<String, dynamic> extras;

  /// AI second read runs: `{id, imageId, at, model, findings: [...]}`.
  final List<Map<String, dynamic>> aiReads;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get imageCount => images.length;
  int get seriesCount => images.map((i) => i.seriesUid).toSet().length;
  bool get hasUnsupportedFiles => images.any((i) => i.compressed);

  bool isOverdue(DateTime now) =>
      status.isOpen && dueAt != null && now.isAfter(dueAt!);

  RadStudy copyWith({
    String? patientId,
    String? patientName,
    String? patientSex,
    DateTime? patientDob,
    RadModality? modality,
    DateTime? studyDate,
    String? description,
    String? referrerId,
    String? clinicalQuestion,
    RadPriority? priority,
    RadStudyStatus? status,
    DateTime? dueAt,
    List<RadImageRef>? images,
    RadDose? dose,
    Map<String, List<RadAnnotation>>? annotations,
    Map<String, double>? calibration,
    List<RadKeyImage>? keyImages,
    bool? critical,
    List<RadCriticalLog>? criticalLog,
    double? fee,
    bool? invoiced,
    Map<String, dynamic>? extras,
    List<Map<String, dynamic>>? aiReads,
  }) =>
      RadStudy(
        id: id,
        patientId: patientId ?? this.patientId,
        patientName: patientName ?? this.patientName,
        patientSex: patientSex ?? this.patientSex,
        patientDob: patientDob ?? this.patientDob,
        patientExternalId: patientExternalId,
        modality: modality ?? this.modality,
        studyDate: studyDate ?? this.studyDate,
        receivedAt: receivedAt,
        description: description ?? this.description,
        referrerId: referrerId ?? this.referrerId,
        clinicalQuestion: clinicalQuestion ?? this.clinicalQuestion,
        priority: priority ?? this.priority,
        status: status ?? this.status,
        dueAt: dueAt ?? this.dueAt,
        images: images ?? this.images,
        dose: dose ?? this.dose,
        studyUid: studyUid,
        accession: accession,
        institution: institution,
        equipment: equipment,
        bodyPart: bodyPart,
        annotations: annotations ?? this.annotations,
        calibration: calibration ?? this.calibration,
        keyImages: keyImages ?? this.keyImages,
        critical: critical ?? this.critical,
        criticalLog: criticalLog ?? this.criticalLog,
        fee: fee ?? this.fee,
        invoiced: invoiced ?? this.invoiced,
        extras: extras ?? this.extras,
        aiReads: aiReads ?? this.aiReads,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientId': patientId,
        'patientName': patientName,
        'patientSex': patientSex,
        'patientDob': patientDob?.millisecondsSinceEpoch,
        'patientExternalId': patientExternalId,
        'modality': modality.name,
        'studyDate': studyDate.millisecondsSinceEpoch,
        'receivedAt': receivedAt.millisecondsSinceEpoch,
        'description': description,
        'referrerId': referrerId,
        'clinicalQuestion': clinicalQuestion,
        'priority': priority.name,
        'status': status.name,
        'dueAt': dueAt?.millisecondsSinceEpoch,
        'images': [for (final i in images) i.toJson()],
        'dose': dose.toJson(),
        'studyUid': studyUid,
        'accession': accession,
        'institution': institution,
        'equipment': equipment,
        'bodyPart': bodyPart,
        'annotations': {
          for (final e in annotations.entries) e.key: [for (final a in e.value) a.toJson()],
        },
        'calibration': calibration,
        'keyImages': [for (final k in keyImages) k.toJson()],
        'critical': critical,
        'criticalLog': [for (final l in criticalLog) l.toJson()],
        'fee': fee,
        'invoiced': invoiced,
        'extras': extras,
        'aiReads': aiReads,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory RadStudy.fromJson(Map<String, dynamic> j) => RadStudy(
        id: _str(j['id']),
        patientId: _str(j['patientId']),
        patientName: _str(j['patientName']),
        patientSex: _str(j['patientSex']),
        patientDob: _date(j['patientDob']),
        patientExternalId: _str(j['patientExternalId']),
        modality: RadModality.fromName(j['modality']),
        studyDate: _date(j['studyDate']) ?? DateTime.now(),
        receivedAt: _date(j['receivedAt']) ?? DateTime.now(),
        description: _str(j['description']),
        referrerId: _str(j['referrerId']),
        clinicalQuestion: _str(j['clinicalQuestion']),
        priority: RadPriority.fromName(j['priority']),
        status: RadStudyStatus.fromName(j['status']),
        dueAt: _date(j['dueAt']),
        images: _list(j['images'], RadImageRef.fromJson),
        dose: RadDose.fromJson(_map(j['dose'])),
        studyUid: _str(j['studyUid']),
        accession: _str(j['accession']),
        institution: _str(j['institution']),
        equipment: _str(j['equipment']),
        bodyPart: _str(j['bodyPart']),
        annotations: {
          for (final e in _map(j['annotations']).entries)
            e.key: _list(e.value, RadAnnotation.fromJson),
        },
        calibration: {
          for (final e in _map(j['calibration']).entries)
            if (e.value is num) e.key: (e.value as num).toDouble(),
        },
        keyImages: _list(j['keyImages'], RadKeyImage.fromJson),
        critical: j['critical'] == true,
        criticalLog: _list(j['criticalLog'], RadCriticalLog.fromJson),
        fee: _double(j['fee']),
        invoiced: j['invoiced'] == true,
        extras: _map(j['extras']),
        aiReads: _list(j['aiReads'], (m) => m),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
      );
}

// ───────────────────────────── Referrer ─────────────────────────────

/// A dentist or clinic that sends scans to be read.
class RadReferrer {
  const RadReferrer({
    required this.id,
    required this.name,
    this.clinic = '',
    this.phone = '',
    this.email = '',
    this.city = '',
    this.regNo = '',
    this.notes = '',
    required this.createdAt,
  });

  final String id;
  final String name;
  final String clinic;
  final String phone;
  final String email;
  final String city;

  /// Dental council registration number.
  final String regNo;
  final String notes;
  final DateTime createdAt;

  String get display => clinic.isEmpty ? name : '$name · $clinic';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'clinic': clinic,
        'phone': phone,
        'email': email,
        'city': city,
        'regNo': regNo,
        'notes': notes,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory RadReferrer.fromJson(Map<String, dynamic> j) => RadReferrer(
        id: _str(j['id']),
        name: _str(j['name']),
        clinic: _str(j['clinic']),
        phone: _str(j['phone']),
        email: _str(j['email']),
        city: _str(j['city']),
        regNo: _str(j['regNo']),
        notes: _str(j['notes']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
      );
}

// ───────────────────────────── Report ─────────────────────────────

enum RadReportStatus {
  draft('Draft'),
  preliminary('Preliminary'),
  finalised('Final');

  const RadReportStatus(this.label);
  final String label;

  static RadReportStatus fromName(Object? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => draft);
}

/// One heading of a report ("Maxillary sinuses") and what was found.
class RadReportSection {
  const RadReportSection({required this.title, this.body = ''});

  final String title;
  final String body;

  RadReportSection copyWith({String? title, String? body}) =>
      RadReportSection(title: title ?? this.title, body: body ?? this.body);

  Map<String, dynamic> toJson() => {'title': title, 'body': body};
  factory RadReportSection.fromJson(Map<String, dynamic> j) =>
      RadReportSection(title: _str(j['title']), body: _str(j['body']));
}

/// The standard description of a lesion (the radiologist's checklist).
class RadLesion {
  const RadLesion({
    required this.id,
    this.location = '',
    this.sizeMm = '',
    this.shape = '',
    this.borders = '',
    this.internal = '',
    this.effects = '',
    this.notes = '',
  });

  final String id;

  /// "Left mandibular body, periapical to 36".
  final String location;

  /// "12 × 9 × 8".
  final String sizeMm;
  final String shape;

  /// "Well-defined, corticated".
  final String borders;

  /// "Radiolucent, unilocular".
  final String internal;

  /// "Displaces the canal inferiorly; thins the buccal cortex".
  final String effects;
  final String notes;

  RadLesion copyWith({
    String? location,
    String? sizeMm,
    String? shape,
    String? borders,
    String? internal,
    String? effects,
    String? notes,
  }) =>
      RadLesion(
        id: id,
        location: location ?? this.location,
        sizeMm: sizeMm ?? this.sizeMm,
        shape: shape ?? this.shape,
        borders: borders ?? this.borders,
        internal: internal ?? this.internal,
        effects: effects ?? this.effects,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'location': location,
        'sizeMm': sizeMm,
        'shape': shape,
        'borders': borders,
        'internal': internal,
        'effects': effects,
        'notes': notes,
      };

  factory RadLesion.fromJson(Map<String, dynamic> j) => RadLesion(
        id: _str(j['id']),
        location: _str(j['location']),
        sizeMm: _str(j['sizeMm']),
        shape: _str(j['shape']),
        borders: _str(j['borders']),
        internal: _str(j['internal']),
        effects: _str(j['effects']),
        notes: _str(j['notes']),
      );
}

/// A saved state of the report (every status change and every signed
/// version), for the version history.
class RadReportVersion {
  const RadReportVersion({
    required this.at,
    required this.status,
    required this.snapshot,
    this.by = '',
  });

  final DateTime at;
  final RadReportStatus status;

  /// The report as plain text at that moment.
  final String snapshot;
  final String by;

  Map<String, dynamic> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'status': status.name,
        'snapshot': snapshot,
        'by': by,
      };

  factory RadReportVersion.fromJson(Map<String, dynamic> j) => RadReportVersion(
        at: _date(j['at']) ?? DateTime.now(),
        status: RadReportStatus.fromName(j['status']),
        snapshot: _str(j['snapshot']),
        by: _str(j['by']),
      );
}

/// Text added to a signed report (it can't be edited once final).
class RadAddendum {
  const RadAddendum({required this.at, required this.text, this.by = ''});

  final DateTime at;
  final String text;
  final String by;

  Map<String, dynamic> toJson() =>
      {'at': at.millisecondsSinceEpoch, 'text': text, 'by': by};

  factory RadAddendum.fromJson(Map<String, dynamic> j) => RadAddendum(
        at: _date(j['at']) ?? DateTime.now(),
        text: _str(j['text']),
        by: _str(j['by']),
      );
}

/// The radiology report for one study.
class RadReport {
  const RadReport({
    required this.id,
    required this.studyId,
    required this.patientId,
    this.templateId = '',
    this.title = '',
    this.technique = '',
    this.sections = const [],
    this.impression = '',
    this.recommendations = '',
    this.status = RadReportStatus.draft,
    this.keyImageIds = const [],
    this.measurementIds = const [],
    this.toothFindings = const {},
    this.lesions = const [],
    this.versions = const [],
    this.addenda = const [],
    this.signedAt,
    this.signedBy = '',
    this.sharedAt,
    this.sharedVia = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String studyId;
  final String patientId;
  final String templateId;

  /// "CBCT report — Implant site assessment".
  final String title;

  /// How the scan was taken (field of view, voxel size, exposure).
  final String technique;
  final List<RadReportSection> sections;
  final String impression;
  final String recommendations;
  final RadReportStatus status;

  /// Key images of the study shown in the report, in order.
  final List<String> keyImageIds;

  /// Annotation ids whose measurements are listed in the report.
  final List<String> measurementIds;

  /// FDI tooth number ("36") to a finding ("Periapical radiolucency").
  final Map<String, String> toothFindings;
  final List<RadLesion> lesions;
  final List<RadReportVersion> versions;
  final List<RadAddendum> addenda;
  final DateTime? signedAt;
  final String signedBy;
  final DateTime? sharedAt;

  /// "WhatsApp", "Email", "Print".
  final String sharedVia;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSigned => status == RadReportStatus.finalised;

  RadReport copyWith({
    String? templateId,
    String? title,
    String? technique,
    List<RadReportSection>? sections,
    String? impression,
    String? recommendations,
    RadReportStatus? status,
    List<String>? keyImageIds,
    List<String>? measurementIds,
    Map<String, String>? toothFindings,
    List<RadLesion>? lesions,
    List<RadReportVersion>? versions,
    List<RadAddendum>? addenda,
    DateTime? signedAt,
    String? signedBy,
    DateTime? sharedAt,
    String? sharedVia,
  }) =>
      RadReport(
        id: id,
        studyId: studyId,
        patientId: patientId,
        templateId: templateId ?? this.templateId,
        title: title ?? this.title,
        technique: technique ?? this.technique,
        sections: sections ?? this.sections,
        impression: impression ?? this.impression,
        recommendations: recommendations ?? this.recommendations,
        status: status ?? this.status,
        keyImageIds: keyImageIds ?? this.keyImageIds,
        measurementIds: measurementIds ?? this.measurementIds,
        toothFindings: toothFindings ?? this.toothFindings,
        lesions: lesions ?? this.lesions,
        versions: versions ?? this.versions,
        addenda: addenda ?? this.addenda,
        signedAt: signedAt ?? this.signedAt,
        signedBy: signedBy ?? this.signedBy,
        sharedAt: sharedAt ?? this.sharedAt,
        sharedVia: sharedVia ?? this.sharedVia,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  /// The report as plain text (version snapshots, sharing as text).
  String toPlainText() {
    final b = StringBuffer();
    if (title.isNotEmpty) b.writeln(title);
    if (technique.trim().isNotEmpty) b..writeln('\nTechnique')..writeln(technique.trim());
    for (final s in sections) {
      if (s.body.trim().isEmpty) continue;
      b..writeln('\n${s.title}')..writeln(s.body.trim());
    }
    if (toothFindings.isNotEmpty) {
      b.writeln('\nTeeth');
      for (final e in toothFindings.entries) {
        b.writeln('${e.key}: ${e.value}');
      }
    }
    if (impression.trim().isNotEmpty) b..writeln('\nImpression')..writeln(impression.trim());
    if (recommendations.trim().isNotEmpty) {
      b..writeln('\nRecommendations')..writeln(recommendations.trim());
    }
    for (final a in addenda) {
      b..writeln('\nAddendum')..writeln(a.text.trim());
    }
    return b.toString().trim();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'studyId': studyId,
        'patientId': patientId,
        'templateId': templateId,
        'title': title,
        'technique': technique,
        'sections': [for (final s in sections) s.toJson()],
        'impression': impression,
        'recommendations': recommendations,
        'status': status.name,
        'keyImageIds': keyImageIds,
        'measurementIds': measurementIds,
        'toothFindings': toothFindings,
        'lesions': [for (final l in lesions) l.toJson()],
        'versions': [for (final v in versions) v.toJson()],
        'addenda': [for (final a in addenda) a.toJson()],
        'signedAt': signedAt?.millisecondsSinceEpoch,
        'signedBy': signedBy,
        'sharedAt': sharedAt?.millisecondsSinceEpoch,
        'sharedVia': sharedVia,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory RadReport.fromJson(Map<String, dynamic> j) => RadReport(
        id: _str(j['id']),
        studyId: _str(j['studyId']),
        patientId: _str(j['patientId']),
        templateId: _str(j['templateId']),
        title: _str(j['title']),
        technique: _str(j['technique']),
        sections: _list(j['sections'], RadReportSection.fromJson),
        impression: _str(j['impression']),
        recommendations: _str(j['recommendations']),
        status: RadReportStatus.fromName(j['status']),
        keyImageIds: _strings(j['keyImageIds']),
        measurementIds: _strings(j['measurementIds']),
        toothFindings: {
          for (final e in _map(j['toothFindings']).entries) e.key: '${e.value}',
        },
        lesions: _list(j['lesions'], RadLesion.fromJson),
        versions: _list(j['versions'], RadReportVersion.fromJson),
        addenda: _list(j['addenda'], RadAddendum.fromJson),
        signedAt: _date(j['signedAt']),
        signedBy: _str(j['signedBy']),
        sharedAt: _date(j['sharedAt']),
        sharedVia: _str(j['sharedVia']),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
      );
}

/// A report layout: headings with their default ("normal") wording.
class RadTemplate {
  const RadTemplate({
    required this.id,
    required this.name,
    required this.modality,
    this.technique = '',
    this.sections = const [],
    this.impression = '',
    this.builtIn = false,
  });

  final String id;
  final String name;

  /// The study type it's the default for.
  final RadModality modality;
  final String technique;
  final List<RadReportSection> sections;
  final String impression;

  /// Shipped with CruDoc (can be copied and changed, not deleted).
  final bool builtIn;

  RadTemplate copyWith({
    String? name,
    RadModality? modality,
    String? technique,
    List<RadReportSection>? sections,
    String? impression,
  }) =>
      RadTemplate(
        id: id,
        name: name ?? this.name,
        modality: modality ?? this.modality,
        technique: technique ?? this.technique,
        sections: sections ?? this.sections,
        impression: impression ?? this.impression,
        builtIn: builtIn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'modality': modality.name,
        'technique': technique,
        'sections': [for (final s in sections) s.toJson()],
        'impression': impression,
        'builtIn': builtIn,
      };

  factory RadTemplate.fromJson(Map<String, dynamic> j) => RadTemplate(
        id: _str(j['id']),
        name: _str(j['name']),
        modality: RadModality.fromName(j['modality']),
        technique: _str(j['technique']),
        sections: _list(j['sections'], RadReportSection.fromJson),
        impression: _str(j['impression']),
        builtIn: j['builtIn'] == true,
      );
}

/// A shortcut phrase: typing the trigger (".sinus") expands the text.
class RadPhrase {
  const RadPhrase({required this.id, required this.trigger, required this.text});

  final String id;

  /// Starts with a dot: ".sinus".
  final String trigger;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'trigger': trigger, 'text': text};
  factory RadPhrase.fromJson(Map<String, dynamic> j) =>
      RadPhrase(id: _str(j['id']), trigger: _str(j['trigger']), text: _str(j['text']));
}

/// The fee for reading one study type.
class RadFee {
  const RadFee({required this.id, required this.label, required this.modality, required this.amount});

  final String id;

  /// "CBCT — full volume".
  final String label;
  final RadModality modality;
  final double amount;

  Map<String, dynamic> toJson() =>
      {'id': id, 'label': label, 'modality': modality.name, 'amount': amount};

  factory RadFee.fromJson(Map<String, dynamic> j) => RadFee(
        id: _str(j['id']),
        label: _str(j['label']),
        modality: RadModality.fromName(j['modality']),
        amount: _double(j['amount']) ?? 0,
      );
}

/// Who did what, when (opened, edited, signed, exported, shared).
class RadAuditEvent {
  const RadAuditEvent({
    required this.id,
    required this.at,
    required this.action,
    this.targetKind = '',
    this.targetId = '',
    this.detail = '',
    this.by = '',
  });

  final String id;
  final DateTime at;

  /// "Opened", "Signed", "Exported"…
  final String action;

  /// "study", "report", "referrer".
  final String targetKind;
  final String targetId;
  final String detail;
  final String by;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'action': action,
        'targetKind': targetKind,
        'targetId': targetId,
        'detail': detail,
        'by': by,
      };

  factory RadAuditEvent.fromJson(Map<String, dynamic> j) => RadAuditEvent(
        id: _str(j['id']),
        at: _date(j['at']) ?? DateTime.now(),
        action: _str(j['action']),
        targetKind: _str(j['targetKind']),
        targetId: _str(j['targetId']),
        detail: _str(j['detail']),
        by: _str(j['by']),
      );
}

/// A PACS reachable over DICOMweb (QIDO-RS search, WADO-RS download,
/// STOW-RS upload). Saved now; the connection comes later.
class RadPacsServer {
  const RadPacsServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.auth = 'none',
    this.username = '',
    this.isDefault = false,
  });

  final String id;
  final String name;

  /// DICOMweb root, e.g. "http://192.168.1.20:8042/dicom-web".
  final String baseUrl;

  /// "none", "basic", "bearer".
  final String auth;
  final String username;
  final bool isDefault;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'auth': auth,
        'username': username,
        'isDefault': isDefault,
      };

  factory RadPacsServer.fromJson(Map<String, dynamic> j) => RadPacsServer(
        id: _str(j['id']),
        name: _str(j['name']),
        baseUrl: _str(j['baseUrl']),
        auth: _str(j['auth']).isEmpty ? 'none' : _str(j['auth']),
        username: _str(j['username']),
        isDefault: j['isDefault'] == true,
      );
}

/// The radiologist's own setup: signature, turnaround times, the DICOM
/// receiver, AI switches and viewer preferences.
class RadSettings {
  const RadSettings({
    this.signatureName = '',
    this.qualification = '',
    this.regNo = '',
    this.tatHours = const {'routine': 48, 'urgent': 24, 'stat': 4},
    this.aeTitle = 'CRUDOC',
    this.dicomPort = 11112,
    this.dicomReceiverOn = false,
    this.aiEnabled = const {},
    this.viewer = const {},
  });

  /// "Dr. Meera Kulkarni" as printed under the signed report.
  final String signatureName;

  /// "MDS (Oral Medicine & Radiology)".
  final String qualification;
  final String regNo;

  /// Turnaround hours by priority name.
  final Map<String, int> tatHours;

  /// The DICOM receiver a scanner sends to ("Send to CruDoc").
  final String aeTitle;
  final int dicomPort;
  final bool dicomReceiverOn;

  /// AI feature switches by key ('secondRead', 'cbct', 'ceph', 'draft',
  /// 'differential'). Off unless turned on.
  final Map<String, bool> aiEnabled;

  /// Viewer preferences owned by the viewer (layouts, window presets,
  /// shortcuts, mouse buttons, 3D presets, last state).
  final Map<String, dynamic> viewer;

  Duration turnaround(RadPriority p) =>
      Duration(hours: tatHours[p.name] ?? const {'routine': 48, 'urgent': 24, 'stat': 4}[p.name]!);

  bool ai(String key) => aiEnabled[key] ?? false;

  RadSettings copyWith({
    String? signatureName,
    String? qualification,
    String? regNo,
    Map<String, int>? tatHours,
    String? aeTitle,
    int? dicomPort,
    bool? dicomReceiverOn,
    Map<String, bool>? aiEnabled,
    Map<String, dynamic>? viewer,
  }) =>
      RadSettings(
        signatureName: signatureName ?? this.signatureName,
        qualification: qualification ?? this.qualification,
        regNo: regNo ?? this.regNo,
        tatHours: tatHours ?? this.tatHours,
        aeTitle: aeTitle ?? this.aeTitle,
        dicomPort: dicomPort ?? this.dicomPort,
        dicomReceiverOn: dicomReceiverOn ?? this.dicomReceiverOn,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        viewer: viewer ?? this.viewer,
      );

  Map<String, dynamic> toJson() => {
        'signatureName': signatureName,
        'qualification': qualification,
        'regNo': regNo,
        'tatHours': tatHours,
        'aeTitle': aeTitle,
        'dicomPort': dicomPort,
        'dicomReceiverOn': dicomReceiverOn,
        'aiEnabled': aiEnabled,
        'viewer': viewer,
      };

  factory RadSettings.fromJson(Map<String, dynamic> j) => RadSettings(
        signatureName: _str(j['signatureName']),
        qualification: _str(j['qualification']),
        regNo: _str(j['regNo']),
        tatHours: {
          'routine': 48,
          'urgent': 24,
          'stat': 4,
          for (final e in _map(j['tatHours']).entries)
            if (e.value is num) e.key: (e.value as num).toInt(),
        },
        aeTitle: _str(j['aeTitle']).isEmpty ? 'CRUDOC' : _str(j['aeTitle']),
        dicomPort: (j['dicomPort'] as num?)?.toInt() ?? 11112,
        dicomReceiverOn: j['dicomReceiverOn'] == true,
        aiEnabled: {
          for (final e in _map(j['aiEnabled']).entries) e.key: e.value == true,
        },
        viewer: _map(j['viewer']),
      );
}
