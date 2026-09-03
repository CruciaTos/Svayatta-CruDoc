import 'package:cloud_firestore/cloud_firestore.dart';

class MedicalDocument {
  final String documentId;
  final String doctorId;
  final String patientId;
  final String documentType;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String storageProvider;
  final String storageKey;
  final String status;
  final String uploadedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final String syncStatus;

  const MedicalDocument({
    required this.documentId,
    required this.doctorId,
    required this.patientId,
    this.documentType = 'other',
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.storageProvider = 'firebase',
    required this.storageKey,
    this.status = 'active',
    required this.uploadedBy,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.syncStatus = 'synced',
  });

  Map<String, dynamic> toLocalMap() {
    return {
      'id': documentId,
      'doctorId': doctorId,
      'patientId': patientId,
      'documentType': documentType,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'storageProvider': storageProvider,
      'storageKey': storageKey,
      'status': status,
      'uploadedBy': uploadedBy,
      'isDeleted': isDeleted ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'doctorId': doctorId,
      'patientId': patientId,
      'documentType': documentType,
      'fileName': fileName,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'storageProvider': storageProvider,
      'storageKey': storageKey,
      'status': status,
      'uploadedBy': uploadedBy,
      'isDeleted': isDeleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory MedicalDocument.fromLocalMap(Map<String, dynamic> map) {
    return MedicalDocument(
      documentId: map['id'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      documentType: map['documentType'] as String? ?? 'other',
      fileName: map['fileName'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      storageProvider: map['storageProvider'] as String? ?? 'firebase',
      storageKey: map['storageKey'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      uploadedBy: map['uploadedBy'] as String? ?? '',
      isDeleted: (map['isDeleted'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int? ?? 0),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
    );
  }

  factory MedicalDocument.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return MedicalDocument(
      documentId: doc.id,
      doctorId: map['doctorId'] as String? ?? '',
      patientId: map['patientId'] as String? ?? '',
      documentType: map['documentType'] as String? ?? 'other',
      fileName: map['fileName'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      storageProvider: map['storageProvider'] as String? ?? 'firebase',
      storageKey: map['storageKey'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      uploadedBy: map['uploadedBy'] as String? ?? '',
      isDeleted: map['isDeleted'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      syncStatus: 'synced',
    );
  }

  MedicalDocument copyWith({
    String? documentType,
    String? fileName,
    String? contentType,
    int? sizeBytes,
    String? storageProvider,
    String? storageKey,
    String? status,
    String? uploadedBy,
    DateTime? updatedAt,
    bool? isDeleted,
    String? syncStatus,
  }) {
    return MedicalDocument(
      documentId: documentId,
      doctorId: doctorId,
      patientId: patientId,
      documentType: documentType ?? this.documentType,
      fileName: fileName ?? this.fileName,
      contentType: contentType ?? this.contentType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      storageProvider: storageProvider ?? this.storageProvider,
      storageKey: storageKey ?? this.storageKey,
      status: status ?? this.status,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
