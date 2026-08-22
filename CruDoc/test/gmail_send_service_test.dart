import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:doctor_management_app/core/errors/gmail_exceptions.dart';
import 'package:doctor_management_app/features/messaging/data/models/generated_document.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_auth_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_send_service.dart';

class MockGmailAuthService extends Mock implements GmailAuthService {}
class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  late MockGmailAuthService mockAuthService;
  late MockHttpClient mockHttpClient;
  late GmailSendService sendService;

  setUp(() {
    mockAuthService = MockGmailAuthService();
    mockHttpClient = MockHttpClient();
    sendService = GmailSendService(
      authService: mockAuthService,
      httpClient: mockHttpClient,
    );

    when(() => mockAuthService.getAuthHeaders()).thenAnswer(
      (_) async => {
        'Authorization': 'Bearer mock_access_token',
        'Content-Type': 'application/json',
      },
    );
    when(() => mockAuthService.connectedEmail).thenReturn('doctor@gmail.com');
  });

  group('Recipient & Header Injection Validation', () {
    test('rejects empty recipient email', () async {
      expect(
        () => sendService.sendEmail(
          to: '   ',
          subject: 'Test Subject',
          body: 'Test Body',
        ),
        throwsA(isA<GmailValidationException>()),
      );
    });

    test('rejects malformed recipient email without @', () async {
      expect(
        () => sendService.sendEmail(
          to: 'invalid-email-address',
          subject: 'Test Subject',
          body: 'Test Body',
        ),
        throwsA(isA<GmailValidationException>()),
      );
    });

    test('blocks CRLF header injection in recipient address', () async {
      expect(
        () => sendService.sendEmail(
          to: "patient@example.com\r\nBcc: hacker@example.com",
          subject: 'Appointment Confirmation',
          body: 'Body text',
        ),
        throwsA(isA<GmailValidationException>()),
      );
    });

    test('strips CRLF from subject line to prevent header splitting', () async {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"id": "msg123", "threadId": "th123"}', 200),
      );

      final result = await sendService.sendEmail(
        to: 'patient@example.com',
        subject: "Subject Line\r\nInjected-Header: evil",
        body: 'Body text',
      );

      expect(result.messageId, 'msg123');
      expect(result.threadId, 'th123');
    });
  });

  group('Attachment Validation & Sanitization', () {
    test('rejects zero-byte attachment', () {
      expect(
        () => GeneratedDocument(
          bytes: Uint8List(0),
          fileName: 'report.pdf',
        ),
        throwsA(isA<GmailValidationException>()),
      );
    });

    test('rejects attachment larger than 20MB', () {
      final oversizedBytes = Uint8List(21 * 1024 * 1024);
      expect(
        () => GeneratedDocument(
          bytes: oversizedBytes,
          fileName: 'huge_scan.pdf',
        ),
        throwsA(isA<GmailValidationException>()),
      );
    });

    test('sanitizes filename containing directory traversal and CRLF', () {
      final doc = GeneratedDocument(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: '../../sensitive_dir/\r\n"prescription".pdf',
      );

      expect(doc.fileName, isNot(contains('/')));
      expect(doc.fileName, isNot(contains(r'\')));
      expect(doc.fileName, isNot(contains('\r')));
      expect(doc.fileName, isNot(contains('\n')));
      expect(doc.fileName, isNot(contains('"')));
      expect(doc.fileName, contains('prescription.pdf'));
    });
  });

  group('MIME Construction & Successful Send', () {
    test('sends plain text email with Unicode subject and body', () async {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"id": "msg_unicode_1", "threadId": "th_1"}', 200),
      );

      final result = await sendService.sendEmail(
        to: 'patient@example.com',
        subject: 'Appointment Confirmation • डॉ. विनीत परब',
        body: 'नमस्ते! Your appointment is confirmed.',
      );

      expect(result.messageId, 'msg_unicode_1');
    });

    test('sends HTML email with text/html Content-Type header', () async {
      String? capturedRawPayload;
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((invocation) async {
        final bodyStr = invocation.namedArguments[const Symbol('body')] as String;
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;
        capturedRawPayload = json['raw'] as String?;
        return http.Response('{"id": "msg_html_1", "threadId": "th_html_1"}', 200);
      });

      final result = await sendService.sendEmail(
        to: 'patient@example.com',
        subject: 'Campaign Update',
        body: '<!DOCTYPE html><html><body><h1>Health Alert</h1></body></html>',
      );

      expect(result.messageId, 'msg_html_1');
      expect(capturedRawPayload, isNotNull);

      // Decode base64url payload and check for text/html
      var normalized = capturedRawPayload!.replaceAll('-', '+').replaceAll('_', '/');
      while (normalized.length % 4 != 0) {
        normalized += '=';
      }
      final decodedMime = utf8.decode(base64Decode(normalized));
      expect(decodedMime, contains('Content-Type: text/html; charset="UTF-8"'));
    });

    test('sends multipart email with multiple attachments', () async {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"id": "msg_multi_att", "threadId": "th_2"}', 200),
      );

      final doc1 = GeneratedDocument(
        bytes: Uint8List.fromList(utf8.encode('PDF Data 1')),
        fileName: 'invoice.pdf',
        mimeType: 'application/pdf',
      );
      final doc2 = GeneratedDocument(
        bytes: Uint8List.fromList(utf8.encode('PNG Data 2')),
        fileName: 'receipt.png',
        mimeType: 'image/png',
      );

      final result = await sendService.sendEmail(
        to: 'patient@example.com',
        subject: 'Your Documents',
        body: 'Please find attached invoice and receipt.',
        attachments: [doc1, doc2],
      );

      expect(result.messageId, 'msg_multi_att');
    });
  });

  group('Error Handling & API Responses', () {
    test('throws GmailAuthRevokedException on HTTP 401', () async {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"error": "unauthorized"}', 401),
      );

      expect(
        () => sendService.sendEmail(
          to: 'patient@example.com',
          subject: 'Test',
          body: 'Test',
        ),
        throwsA(isA<GmailAuthRevokedException>()),
      );
    });

    test('throws GmailRateLimitException on HTTP 429', () async {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"error": "rate limit exceeded"}', 429),
      );

      expect(
        () => sendService.sendEmail(
          to: 'patient@example.com',
          subject: 'Test',
          body: 'Test',
        ),
        throwsA(isA<GmailRateLimitException>()),
      );
    });

    test('throws GmailSendException on HTTP 500', () async {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"error": "backend error"}', 500),
      );

      expect(
        () => sendService.sendEmail(
          to: 'patient@example.com',
          subject: 'Test',
          body: 'Test',
        ),
        throwsA(isA<GmailSendException>()),
      );
    });
  });
}
