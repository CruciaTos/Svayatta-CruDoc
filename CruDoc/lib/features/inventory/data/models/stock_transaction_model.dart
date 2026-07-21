import 'package:cloud_firestore/cloud_firestore.dart';

/// The kind of movement a [StockTransactionModel] represents.
enum StockTransactionType {
  restock,
  dispense,
  adjustment,
  expiredWriteoff;

  /// Storage value used in both SQLite and Firestore (snake_case, matching
  /// the spec's `expired_writeoff` wire value).
  String get stored {
    switch (this) {
      case StockTransactionType.restock:
        return 'restock';
      case StockTransactionType.dispense:
        return 'dispense';
      case StockTransactionType.adjustment:
        return 'adjustment';
      case StockTransactionType.expiredWriteoff:
        return 'expired_writeoff';
    }
  }

  static StockTransactionType fromStored(String? value) {
    switch (value) {
      case 'dispense':
        return StockTransactionType.dispense;
      case 'adjustment':
        return StockTransactionType.adjustment;
      case 'expired_writeoff':
        return StockTransactionType.expiredWriteoff;
      case 'restock':
      default:
        return StockTransactionType.restock;
    }
  }

  /// Whether this transaction type increases (`true`) or decreases
  /// (`false`) `currentStock` when applied. `adjustment` can go either way
  /// and is handled by [StockTransactionModel.signedQuantity] using the
  /// signed quantity passed in by the caller instead.
  bool get increasesStock => this == StockTransactionType.restock;
}

/// A single stock movement for a medicine — a restock, a dispense to a
/// patient, a manual adjustment, or a write-off of expired stock.
///
/// Mirrors the `stock_transactions` SQLite table / Firestore collection.
class StockTransactionModel {
  final String id;
  final String medicineId;
  final String doctorId;
  final StockTransactionType type;

  /// Always stored as a positive count; the sign of its effect on
  /// `currentStock` is implied by [type] (see [InventoryLocalService]).
  final int quantity;

  /// Snapshot of the medicine's `currentStock` immediately after this
  /// transaction was applied, kept for audit-trail display.
  final int resultingStock;

  final String? note;
  final String? linkedVisitId;
  final DateTime createdAt;

  const StockTransactionModel({
    required this.id,
    required this.medicineId,
    this.doctorId = '',
    required this.type,
    required this.quantity,
    required this.resultingStock,
    this.note,
    this.linkedVisitId,
    required this.createdAt,
  });

  factory StockTransactionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return StockTransactionModel.fromJson(data, id: doc.id);
  }

  factory StockTransactionModel.fromJson(
    Map<String, dynamic> map, {
    String? id,
  }) {
    return StockTransactionModel(
      id: id ?? map['id'] as String? ?? '',
      medicineId: map['medicineId'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      type: StockTransactionType.fromStored(map['type'] as String?),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      resultingStock: (map['resultingStock'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      linkedVisitId: map['linkedVisitId'] as String?,
      createdAt: _toDate(map['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'medicineId': medicineId,
      'doctorId': doctorId,
      'type': type.stored,
      'quantity': quantity,
      'resultingStock': resultingStock,
      'note': note,
      'linkedVisitId': linkedVisitId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }
}
