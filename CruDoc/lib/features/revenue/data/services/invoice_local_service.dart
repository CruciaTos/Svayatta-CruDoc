import 'package:flutter/foundation.dart';
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/services/local_database_service.dart';
import 'package:doctor_management_app/features/revenue/data/models/invoice_model.dart';

class InvoiceLocalService {
  InvoiceLocalService({LocalDatabaseService? dbService})
      : _dbService = dbService ?? LocalDatabaseService.instance;

  final LocalDatabaseService _dbService;

  Future<void> _ensureTableCreated(LocalDatabase db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id TEXT PRIMARY KEY,
        doctorId TEXT NOT NULL DEFAULT '',
        patientId TEXT,
        patientName TEXT NOT NULL DEFAULT '',
        service TEXT NOT NULL DEFAULT '',
        amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Pending',
        date INTEGER NOT NULL,
        dueDate INTEGER,
        notes TEXT,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
  }

  Future<void> upsertInvoice(InvoiceModel invoice) async {
    if (kIsWeb) return;
    final db = await _dbService.localDatabase;
    await _ensureTableCreated(db);

    await db.insert(
      'invoices',
      invoice.toMap(),
      conflictAlgorithm: LocalConflictAlgorithm.replace,
    );
  }

  Future<List<InvoiceModel>> getInvoicesForDoctor(String doctorId) async {
    if (kIsWeb) return [];
    if (doctorId.trim().isEmpty) return [];

    final db = await _dbService.localDatabase;
    await _ensureTableCreated(db);

    final maps = await db.query(
      'invoices',
      where: 'doctorId = ?',
      whereArgs: [doctorId],
      orderBy: 'createdAt DESC',
    );

    return maps.map((m) => InvoiceModel.fromMap(m)).toList();
  }

  Future<void> deleteInvoice(String id, String doctorId) async {
    if (kIsWeb) return;
    final db = await _dbService.localDatabase;
    await _ensureTableCreated(db);

    await db.delete(
      'invoices',
      where: 'id = ? AND doctorId = ?',
      whereArgs: [id, doctorId],
    );
  }
}