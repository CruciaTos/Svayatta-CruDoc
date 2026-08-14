/// Base exception class for all Gmail-related domain errors.
///
/// Patterned after [RevenueException] and [VisitException] in CruDoc.
/// Guarantees that sensitive information (OAuth tokens, client secrets,
/// raw HTTP payloads) are never exposed via [message] or [toString].
sealed class GmailException implements Exception {
  final String message;
  const GmailException(this.message);

  @override
  String toString() => message;
}

/// Thrown when the doctor explicitly cancels the Google OAuth consent flow.
class GmailAuthCancelledException extends GmailException {
  const GmailAuthCancelledException([
    super.message = 'Gmail authentication was cancelled by the user.',
  ]);
}

/// Thrown when stored OAuth credentials have been revoked by the doctor
/// from their Google Account settings, or the refresh token is no longer valid.
class GmailAuthRevokedException extends GmailException {
  const GmailAuthRevokedException([
    super.message = 'Gmail access has been revoked. Please reconnect your Gmail account.',
  ]);
}

/// Thrown when the access token has expired and silent refresh failed.
class GmailTokenExpiredException extends GmailException {
  const GmailTokenExpiredException([
    super.message = 'Gmail session expired. Please sign in again.',
  ]);
}

/// Thrown when Gmail API rate limits or quota thresholds are exceeded (HTTP 429).
class GmailRateLimitException extends GmailException {
  const GmailRateLimitException([
    super.message = 'Gmail rate limit reached. Please try again later.',
  ]);
}

/// Thrown when email fields fail client-side validation
/// (malformed address, CRLF injection attempt, oversized attachment).
class GmailValidationException extends GmailException {
  const GmailValidationException(super.message);
}

/// Thrown when the Gmail API returns a non-success response (e.g. 5xx or bad request).
class GmailSendException extends GmailException {
  final int? statusCode;
  const GmailSendException(super.message, {this.statusCode});
}

/// Thrown when network connectivity fails during an OAuth or send request.
class GmailNetworkException extends GmailException {
  const GmailNetworkException([
    super.message = 'Network error while communicating with Gmail. Check your internet connection.',
  ]);
}
