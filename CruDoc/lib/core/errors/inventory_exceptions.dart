/// Thrown by [InventoryRepository] when a medicine fails basic validation
/// (e.g. an empty name or a negative reorder threshold). Kept as a
/// distinct, typed exception so calling UI code can catch it specifically
/// and show a friendly message, instead of parsing a generic error.
class MedicineValidationException implements Exception {
  final String message;
  const MedicineValidationException(this.message);

  @override
  String toString() => message;
}

/// Thrown when an operation references a medicine id that doesn't exist
/// (or isn't active) in the local store.
class MedicineNotFoundException implements Exception {
  final String message;
  const MedicineNotFoundException(this.message);

  @override
  String toString() => message;
}

/// Thrown when a `dispense` or `expired_writeoff` stock transaction would
/// take a medicine's `currentStock` below zero.
class InsufficientStockException implements Exception {
  final String message;
  const InsufficientStockException(this.message);

  @override
  String toString() => message;
}
