/// Base type for every revenue-related domain error thrown by
/// `RevenueRepository`. Lets calling code `catch (e) { if (e is
/// RevenueException) ... }` to handle all of them generically, or catch
/// a specific subtype when it needs to react differently.
sealed class RevenueException implements Exception {
  final String message;
  const RevenueException(this.message);

  @override
  String toString() => message;
}

/// A required field was missing, empty, or out of the allowed range
/// (e.g. a blank description, a zero or negative amount).
class RevenueValidationException extends RevenueException {
  const RevenueValidationException(super.message);
}

/// No `PendingPayment` exists with the given id — thrown by
/// `RevenueRepository.markPendingPaymentAsPaid` when the id doesn't
/// resolve to a real, still-unpaid document (e.g. it was already
/// marked paid, or the id is stale).
class PendingPaymentNotFoundException extends RevenueException {
  PendingPaymentNotFoundException(String pendingPaymentId)
    : super('No pending payment found with id "$pendingPaymentId".');
}