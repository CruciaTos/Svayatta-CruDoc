import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/chatbot/services/chatbot_service.dart';
import 'package:doctor_management_app/features/chatbot/services/voice_transcription_service.dart';
import 'package:doctor_management_app/features/chatbot/widgets/chat_bubble.dart';

void main() {
  group('ChatMessage & ChatbotService Comprehensive App Knowledge Tests', () {
    test('ChatMessage model creates valid instances with custom IDs and error flags', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        id: 'msg-123',
        text: 'How do I add a patient?',
        isUser: true,
        timestamp: now,
        isError: false,
      );

      expect(msg.id, equals('msg-123'));
      expect(msg.text, equals('How do I add a patient?'));
      expect(msg.isUser, isTrue);
      expect(msg.timestamp, equals(now));
      expect(msg.isError, isFalse);
    });

    test('ChatbotService answers patient management questions', () async {
      final service = ChatbotService.instance;
      service.resetConversation();

      final response = await service.sendMessage('How to add a patient?');
      expect(response, contains('Patient Records'));
      expect(response, contains('Adding a New Patient'));

      final vitalsResponse = await service.sendMessage('Where to view patient vitals and medical history?');
      expect(vitalsResponse, contains('Patient Medical Details'));
      expect(vitalsResponse, contains('Vitals'));
    });

    test('ChatbotService answers AI Voice Scribe questions', () async {
      final service = ChatbotService.instance;
      service.resetConversation();

      final response = await service.sendMessage('How does AI Voice Scribe work?');
      expect(response, contains('AI Voice Scribe'));
      expect(response, contains('Chief Complaint'));
      expect(response, contains('Suggested Diagnoses'));
      expect(response, contains('Prescription'));
    });

    test('ChatbotService answers Patient Campaign questions', () async {
      final service = ChatbotService.instance;
      service.resetConversation();

      final campaignResponse = await service.sendMessage('schedule a campaign');
      expect(campaignResponse, contains('Scheduling & Running a Campaign'));
      expect(campaignResponse, contains('Campaigns'));
      expect(campaignResponse, contains('Audience'));
    });

    test('ChatbotService answers Invoicing & Revenue PDF questions', () async {
      final service = ChatbotService.instance;
      service.resetConversation();

      final invoiceResponse = await service.sendMessage('How to create an invoice?');
      expect(invoiceResponse, contains('Creating an Invoice'));
      expect(invoiceResponse, contains('Revenue'));

      final pdfResponse = await service.sendMessage('How to export invoice PDF?');
      expect(pdfResponse, contains('Exporting & Sharing Invoice PDFs'));
      expect(pdfResponse, contains('PDF'));

      final hideResponse = await service.sendMessage('How to hide revenue on dashboard?');
      expect(hideResponse, contains('Hiding Revenue'));
      expect(hideResponse, contains('eye icon'));
    });

    test('ChatbotService answers Inventory & Stock questions', () async {
      final service = ChatbotService.instance;
      service.resetConversation();

      final stockResponse = await service.sendMessage('How to adjust medicine stock?');
      expect(stockResponse, contains('Inventory & Stock Management'));
      expect(stockResponse, contains('Adjust Stock'));
    });

    test('ChatbotService answers Navigation & Tab questions', () async {
      final service = ChatbotService.instance;
      service.resetConversation();

      final navResponse = await service.sendMessage('How to navigate the app?');
      expect(navResponse, contains('App Navigation Guide'));
      expect(navResponse, contains('Dashboard'));
      expect(navResponse, contains('Patients'));
      expect(navResponse, contains('Inventory'));
      expect(navResponse, contains('Revenue'));
      expect(navResponse, contains('Appointments'));
      expect(navResponse, contains('Campaigns'));
    });

    test('ChatbotService detects locked features when modules are restricted', () async {
      final service = ChatbotService.instance;
      service.resetConversation();

      final enabledModules = ['dashboard', 'appointments'];
      final response = await service.sendMessage(
        'How to create an invoice?',
        enabledModules: enabledModules,
      );

      expect(response, contains('Feature Locked'));
      expect(response, contains('Revenue & Invoices'));
    });
  });

  group('ChatBubble Markdown & UI Tests', () {
    testWidgets('ChatBubble renders user message with gradient and checkmark', (tester) async {
      final now = DateTime(2026, 8, 28, 10, 30);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              text: 'How do I manage inventory?',
              isUser: true,
              timestamp: now,
            ),
          ),
        ),
      );

      expect(find.text('How do I manage inventory?'), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.text('10:30 AM'), findsOneWidget);
    });

    testWidgets('ChatBubble parses markdown headers, bullet lists, and bold text', (tester) async {
      final now = DateTime(2026, 8, 28, 14, 45);
      const markdown = '### Clinical Overview\n• **Step 1**: Check vitals\n• **Step 2**: Prescribe `Paracetamol`';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              text: markdown,
              isUser: false,
              timestamp: now,
            ),
          ),
        ),
      );

      expect(find.text('Clinical Overview'), findsOneWidget);
      expect(find.text('• '), findsNWidgets(2));
      expect(find.byIcon(Icons.smart_toy_rounded), findsOneWidget);
      expect(find.text('2:45 PM'), findsOneWidget);
    });

    testWidgets('ChatBubble displays retry button on error state', (tester) async {
      final now = DateTime.now();
      bool retryTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              text: 'Connection failed',
              isUser: false,
              timestamp: now,
              isError: true,
              onRetry: () {
                retryTriggered = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.text('Tap to retry query'), findsOneWidget);

      await tester.tap(find.text('Tap to retry query'));
      expect(retryTriggered, isTrue);
    });

    testWidgets('TypingIndicator animates and renders bot icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TypingIndicator(),
          ),
        ),
      );

      expect(find.text('CruDoc AI thinking...'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_rounded), findsOneWidget);
    });
  });

  group('VoiceTranscriptionService Tests', () {
    test('VoiceTranscriptionException holds readable error message', () {
      const exception = VoiceTranscriptionException('Microphone not available');
      expect(exception.toString(), equals('Microphone not available'));
    });
  });
}
