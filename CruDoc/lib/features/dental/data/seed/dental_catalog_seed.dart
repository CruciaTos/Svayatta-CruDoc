import 'package:uuid/uuid.dart';
import '../models/dental_procedure_catalog_model.dart';
import '../repositories/dental_repository.dart';

/// Idempotent starter catalog seed for new dental clinics.
class DentalCatalogSeed {
  static const _uuid = Uuid();

  /// Default common procedure templates for Indian dental practices.
  static List<Map<String, dynamic>> get defaultTemplates => const [
        {
          'code': 'CONS',
          'name': 'Dental Consultation',
          'category': 'general',
          'defaultPrice': 300.0,
          'defaultDurationMinutes': 15,
          'requiresToothSelection': false,
        },
        {
          'code': 'SCALE',
          'name': 'Scaling & Polishing (Full Mouth)',
          'category': 'preventive',
          'defaultPrice': 1500.0,
          'defaultDurationMinutes': 30,
          'requiresToothSelection': false,
        },
        {
          'code': 'FILL_COMP',
          'name': 'Composite Restoration',
          'category': 'restorative',
          'defaultPrice': 1200.0,
          'defaultDurationMinutes': 30,
          'requiresToothSelection': true,
        },
        {
          'code': 'RCT',
          'name': 'Root Canal Treatment',
          'category': 'endodontics',
          'defaultPrice': 4000.0,
          'defaultDurationMinutes': 60,
          'requiresToothSelection': true,
        },
        {
          'code': 'EXT_SIMPLE',
          'name': 'Simple Tooth Extraction',
          'category': 'surgery',
          'defaultPrice': 1000.0,
          'defaultDurationMinutes': 30,
          'requiresToothSelection': true,
        },
        {
          'code': 'EXT_SURG',
          'name': 'Surgical / Disimpaction Extraction',
          'category': 'surgery',
          'defaultPrice': 3500.0,
          'defaultDurationMinutes': 45,
          'requiresToothSelection': true,
        },
        {
          'code': 'CROWN_PFM',
          'name': 'Porcelain Fused to Metal (PFM) Crown',
          'category': 'prosthodontics',
          'defaultPrice': 3500.0,
          'defaultDurationMinutes': 45,
          'requiresToothSelection': true,
        },
        {
          'code': 'CROWN_ZIRC',
          'name': 'Monolithic Zirconia Crown',
          'category': 'prosthodontics',
          'defaultPrice': 7500.0,
          'defaultDurationMinutes': 45,
          'requiresToothSelection': true,
        },
        {
          'code': 'IMP_SINGLE',
          'name': 'Single Dental Implant',
          'category': 'implantology',
          'defaultPrice': 25000.0,
          'defaultDurationMinutes': 60,
          'requiresToothSelection': true,
        },
        {
          'code': 'XRAY_IOPA',
          'name': 'Intraoral Periapical X-Ray (IOPA)',
          'category': 'diagnostics',
          'defaultPrice': 250.0,
          'defaultDurationMinutes': 10,
          'requiresToothSelection': true,
        },
        {
          'code': 'XRAY_OPG',
          'name': 'Panoramic Radiograph (OPG)',
          'category': 'diagnostics',
          'defaultPrice': 800.0,
          'defaultDurationMinutes': 15,
          'requiresToothSelection': false,
        },
      ];

  /// Seeds default dental procedures for [doctorId] if missing.
  /// Idempotent: existing procedure codes for this doctor are untouched and never overwritten.
  static Future<int> seedIfNeeded(DentalRepository repository, String doctorId) async {
    if (doctorId.trim().isEmpty) return 0;

    final existing = await repository.getProcedureCatalog(doctorId);
    final existingCodes = existing.map((e) => e.code.toUpperCase()).toSet();

    int insertedCount = 0;
    final now = DateTime.now();

    for (final template in defaultTemplates) {
      final code = template['code'] as String;
      if (existingCodes.contains(code.toUpperCase())) {
        continue; // preserve existing clinic edits
      }

      final newItem = DentalProcedureCatalogModel(
        id: _uuid.v4(),
        doctorId: doctorId,
        code: code,
        name: template['name'] as String,
        category: template['category'] as String,
        defaultPrice: template['defaultPrice'] as double?,
        defaultDurationMinutes: template['defaultDurationMinutes'] as int?,
        requiresToothSelection: template['requiresToothSelection'] as bool? ?? true,
        isActive: true,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      await repository.saveCatalogItem(newItem);
      insertedCount++;
    }

    return insertedCount;
  }
}
