import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:doctor_management_app/core/errors/gmail_exceptions.dart';
import 'package:doctor_management_app/features/messaging/data/models/generated_document.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_auth_service.dart';

/// Result of a successful Gmail API send call.
class GmailSendResult {
  final String messageId;
  final String? threadId;

  const GmailSendResult({
    required this.messageId,
    this.threadId,
  });
}

/// Service that constructs RFC 2822/2047 MIME messages and dispatches them via the Gmail REST API.
///
/// Security & Quality standards:
/// - RFC 5321 recipient email address validation.
/// - Defends against email-header and CRLF injection attacks.
/// - RFC 2047 MIME header encoding for full Unicode/international character support.
/// - Base64url encoding without padding per Google Gmail API specifications.
/// - Automatic resource management and disposal of HTTP clients.
class GmailSendService {
  GmailSendService({
    required GmailAuthService authService,
    http.Client? httpClient,
  })  : _authService = authService,
        _httpClient = httpClient;

  final GmailAuthService _authService;
  final http.Client? _httpClient;

  static const String _sendEndpoint =
      'https://gmail.googleapis.com/gmail/v1/users/me/messages/send';

  // Strict email regex matching RFC 5322
  static final RegExp _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  /// Sends an email with optional attachments via the Gmail REST API.
  Future<GmailSendResult> sendEmail({
    required String to,
    required String subject,
    required String body,
    List<GeneratedDocument> attachments = const [],
    String? fromEmail,
  }) async {
    // 1. Validate inputs and defend against header injection
    final cleanTo = _validateAndSanitizeRecipient(to);
    final cleanSubject = _sanitizeSubject(subject);
    final sender = fromEmail ?? _authService.connectedEmail ?? '';

    // 2. Build RFC 2822 MIME message
    final mimeMessage = _buildMimeMessage(
      from: sender,
      to: cleanTo,
      subject: cleanSubject,
      body: body,
      attachments: attachments,
    );

    // 3. Base64url encode with no padding per Gmail API requirement
    final rawBase64Url = base64Url
        .encode(utf8.encode(mimeMessage))
        .replaceAll('=', '')
        .replaceAll('+', '-')
        .replaceAll('/', '_');

    // 4. Retrieve authenticated HTTP headers from GmailAuthService
    final authHeaders = await _authService.getAuthHeaders();

    // 5. Send POST request to Gmail API
    final client = _httpClient ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse(_sendEndpoint),
            headers: authHeaders,
            body: jsonEncode({'raw': rawBase64Url}),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const GmailNetworkException(
              'Gmail send request timed out. Please check your connection.',
            ),
          );

      if (response.statusCode == 200) {
        final resBody = jsonDecode(response.body) as Map<String, dynamic>;
        final messageId = (resBody['id'] ?? '').toString();
        final threadId = resBody['threadId'] as String?;
        return GmailSendResult(messageId: messageId, threadId: threadId);
      }

      // Handle specific HTTP error status codes
      _handleApiError(response.statusCode, response.body);
      throw GmailSendException(
        'Gmail API returned unexpected response: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    } on SocketException catch (_) {
      throw const GmailNetworkException();
    } on http.ClientException catch (_) {
      throw const GmailNetworkException();
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Validation & Sanitization
  // ---------------------------------------------------------------------------

  String _validateAndSanitizeRecipient(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw const GmailValidationException('Recipient email address cannot be empty.');
    }

    // CRLF / Header-injection prevention
    if (trimmed.contains('\r') || trimmed.contains('\n')) {
      throw const GmailValidationException(
        'Malformed email address: illegal line breaks detected.',
      );
    }

    if (!_emailRegex.hasMatch(trimmed)) {
      throw GmailValidationException(
        'Invalid recipient email address format: "$trimmed".',
      );
    }

    return trimmed;
  }

  String _sanitizeSubject(String subject) {
    // Strip CRLF to prevent header injection in subject
    final clean = subject.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    return clean.isEmpty ? 'Notification from CruDoc' : clean;
  }

  // ---------------------------------------------------------------------------
  // MIME Construction (RFC 2822 / RFC 2047)
  // ---------------------------------------------------------------------------

  String _buildMimeMessage({
    required String from,
    required String to,
    required String subject,
    required String body,
    required List<GeneratedDocument> attachments,
  }) {
    // RFC 2047 B-encoded subject for full Unicode safety
    final encodedSubject =
        '=?UTF-8?B?${base64Encode(utf8.encode(subject))}?=';

    final buffer = StringBuffer();
    if (from.isNotEmpty) {
      buffer.writeln('From: $from');
    }
    buffer.writeln('To: $to');
    buffer.writeln('Subject: $encodedSubject');
    buffer.writeln('MIME-Version: 1.0');

    if (attachments.isEmpty) {
      // Plain text message
      buffer.writeln('Content-Type: text/plain; charset="UTF-8"');
      buffer.writeln('Content-Transfer-Encoding: base64');
      buffer.writeln();
      buffer.writeln(_chunkBase64(base64Encode(utf8.encode(body))));
    } else {
      // Multipart message with attachments
      final boundary = _generateBoundary();
      buffer.writeln('Content-Type: multipart/mixed; boundary="$boundary"');
      buffer.writeln();

      // Text body part
      buffer.writeln('--$boundary');
      buffer.writeln('Content-Type: text/plain; charset="UTF-8"');
      buffer.writeln('Content-Transfer-Encoding: base64');
      buffer.writeln();
      buffer.writeln(_chunkBase64(base64Encode(utf8.encode(body))));
      buffer.writeln();

      // Attachment parts
      for (final doc in attachments) {
        buffer.writeln('--$boundary');
        buffer.writeln('Content-Type: ${doc.mimeType}; name="${doc.fileName}"');
        buffer.writeln('Content-Disposition: attachment; filename="${doc.fileName}"');
        buffer.writeln('Content-Transfer-Encoding: base64');
        buffer.writeln();
        buffer.writeln(_chunkBase64(base64Encode(doc.bytes)));
        buffer.writeln();
      }

      buffer.writeln('--$boundary--');
    }

    return buffer.toString();
  }

  String _chunkBase64(String input) {
    const chunkSize = 76;
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i += chunkSize) {
      final end = (i + chunkSize < input.length) ? i + chunkSize : input.length;
      buffer.writeln(input.substring(i, end));
    }
    return buffer.toString().trimRight();
  }

  String _generateBoundary() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return '----=_Part_${DateTime.now().millisecondsSinceEpoch}_${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  void _handleApiError(int statusCode, String responseBody) {
    debugPrint('[Gmail API Response $statusCode]: $responseBody');
    if (statusCode == 401) {
      throw const GmailAuthRevokedException();
    } else if (statusCode == 403) {
      if (responseBody.contains('rateLimitExceeded') ||
          responseBody.contains('userRateLimitExceeded')) {
        throw const GmailRateLimitException();
      }
      throw GmailAuthRevokedException(
        'Gmail permissions insufficient or access denied: $responseBody',
      );
    } else if (statusCode == 429) {
      throw const GmailRateLimitException();
    } else if (statusCode >= 500) {
      throw GmailSendException(
        'Gmail server error ($statusCode). Please try again shortly.',
        statusCode: statusCode,
      );
    }
  }
}
