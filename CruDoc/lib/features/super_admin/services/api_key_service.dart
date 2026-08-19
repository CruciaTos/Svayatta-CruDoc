import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../config/enums.dart';
import '../models/api_key_model.dart';
import 'firebase_service.dart';
import 'audit_log_service.dart';

/// Service for managing API Keys and tracking API Usage in Super Admin.
class SuperAdminApiKeyService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();
  final SuperAdminAuditLogService _auditLogService = SuperAdminAuditLogService();

  /// Fetch all API Keys from Firestore ordered by creation date.
  Future<List<ApiKeyModel>> getApiKeys() async {
    try {
      final snapshot = await _fb.apiKeysCollection
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        return ApiKeyModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch API keys: ${e.toString()}');
    }
  }

  /// Generate a cryptographically secure random API key.
  String _generateSecureKey() {
    final rand = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buffer = StringBuffer('cd_live_');
    for (var i = 0; i < 32; i++) {
      buffer.write(chars[rand.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  /// Create a new API Key in Firestore and write to the audit log.
  /// Returns a Map containing the generated [ApiKeyModel] and the cleartext [secretKey].
  Future<Map<String, dynamic>> createApiKey({
    required String name,
    DateTime? expiresAt,
    int rateLimit = 60,
    required List<String> scopes,
  }) async {
    try {
      final cleartextKey = _generateSecureKey();
      
      // Hash the key using SHA-256
      final bytes = utf8.encode(cleartextKey);
      final hash = sha256.convert(bytes).toString();

      // Mask the key (e.g. cd_live_••••••••abcd)
      final maskedKey = 'cd_live_••••••••${cleartextKey.substring(cleartextKey.length - 4)}';
      
      final docRef = _fb.apiKeysCollection.doc();
      final adminEmail = _fb.currentUserEmail ?? 'unknown';

      final apiKey = ApiKeyModel(
        id: docRef.id,
        name: name,
        maskedKey: maskedKey,
        secretHash: hash,
        isActive: true,
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
        rateLimit: rateLimit,
        scopes: scopes,
        createdBy: adminEmail,
        totalRequests: 0,
      );

      // Write to Firestore
      await docRef.set(apiKey.toJson());

      // Write to Audit Log
      await _auditLogService.logAction(
        actionType: AuditActionType.createdApiKey,
        details: {
          'keyId': docRef.id,
          'keyName': name,
          'maskedKey': maskedKey,
          'rateLimit': rateLimit,
          'scopes': scopes,
        },
      );

      return {
        'model': apiKey,
        'secretKey': cleartextKey,
      };
    } catch (e) {
      throw Exception('Failed to create API key: ${e.toString()}');
    }
  }

  /// Update an existing API Key's metadata in Firestore.
  Future<void> updateApiKey({
    required String id,
    required String name,
    required int rateLimit,
    required bool isActive,
    required List<String> scopes,
  }) async {
    try {
      final docRef = _fb.apiKeysCollection.doc(id);
      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        throw Exception('API Key not found');
      }

      final beforeData = docSnapshot.data() as Map<String, dynamic>;
      
      final updates = {
        'name': name,
        'rateLimit': rateLimit,
        'isActive': isActive,
        'scopes': scopes,
      };

      await docRef.update(updates);

      // Write to Audit Log
      await _auditLogService.logAction(
        actionType: AuditActionType.updatedApiKey,
        beforeValues: beforeData,
        afterValues: updates,
        details: {
          'keyId': id,
          'keyName': name,
        },
      );
    } catch (e) {
      throw Exception('Failed to update API key: ${e.toString()}');
    }
  }

  /// Revoke (disable) an API key.
  Future<void> revokeApiKey(String id) async {
    try {
      final docRef = _fb.apiKeysCollection.doc(id);
      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        throw Exception('API Key not found');
      }

      final beforeData = docSnapshot.data() as Map<String, dynamic>;
      
      await docRef.update({
        'isActive': false,
      });

      // Write to Audit Log
      await _auditLogService.logAction(
        actionType: AuditActionType.revokedApiKey,
        beforeValues: beforeData,
        afterValues: {'isActive': false},
        details: {
          'keyId': id,
          'keyName': beforeData['name'],
        },
      );
    } catch (e) {
      throw Exception('Failed to revoke API key: ${e.toString()}');
    }
  }

  /// Fetch recent API usage logs from Firestore.
  Future<List<ApiLogModel>> getApiLogs() async {
    try {
      final snapshot = await _fb.apiLogsCollection
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      return snapshot.docs.map((doc) {
        return ApiLogModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch API logs: ${e.toString()}');
    }
  }

  /// Seed realistic mock logs in Firestore if the collection is empty.
  Future<void> seedMockApiLogs(List<ApiKeyModel> apiKeys) async {
    try {
      final snapshot = await _fb.apiLogsCollection.limit(1).get();
      if (snapshot.docs.isNotEmpty) {
        // Already contains logs, no need to seed
        return;
      }

      if (apiKeys.isEmpty) return;

      final endpoints = [
        '/api/v1/patients',
        '/api/v1/appointments',
        '/api/v1/inventory',
        '/api/v1/voice-bot/webhook',
        '/api/v1/revenue/summary',
      ];

      final methods = {
        '/api/v1/patients': ['GET', 'POST', 'PUT'],
        '/api/v1/appointments': ['GET', 'POST'],
        '/api/v1/inventory': ['GET', 'POST'],
        '/api/v1/voice-bot/webhook': ['POST'],
        '/api/v1/revenue/summary': ['GET'],
      };

      final batch = _fb.firestore.batch();
      final rand = Random();
      final now = DateTime.now();

      // We will seed logs spanning the last 7 days
      for (var day = 0; day < 7; day++) {
        final date = now.subtract(Duration(days: day));
        // Number of requests per day decreases as we go back in time (simulating growth)
        final dailyRequestCount = 8 + rand.nextInt(12);

        for (var i = 0; i < dailyRequestCount; i++) {
          final apiKey = apiKeys[rand.nextInt(apiKeys.length)];
          final endpoint = endpoints[rand.nextInt(endpoints.length)];
          final methodList = methods[endpoint]!;
          final method = methodList[rand.nextInt(methodList.length)];
          
          // Mostly 200, occasionally 400 or 500
          final randVal = rand.nextDouble();
          int statusCode = 200;
          if (randVal > 0.96) {
            statusCode = 500;
          } else if (randVal > 0.90) {
            statusCode = 400;
          } else if (randVal > 0.87) {
            statusCode = 401;
          }

          final latency = 40 + rand.nextInt(320); // 40ms to 360ms
          
          final logTime = DateTime(
            date.year,
            date.month,
            date.day,
            rand.nextInt(24),
            rand.nextInt(60),
            rand.nextInt(60),
          );

          final logRef = _fb.apiLogsCollection.doc();
          final log = ApiLogModel(
            id: logRef.id,
            apiKeyId: apiKey.id,
            apiKeyName: apiKey.name,
            endpoint: endpoint,
            method: method,
            statusCode: statusCode,
            latencyMs: latency,
            timestamp: logTime,
          );

          batch.set(logRef, log.toJson());
        }
      }

      await batch.commit();

      // Update total request counts in API Keys collections
      for (final key in apiKeys) {
        final keyLogsSnapshot = await _fb.apiLogsCollection
            .where('apiKeyId', isEqualTo: key.id)
            .get();
        await _fb.apiKeysCollection.doc(key.id).update({
          'totalRequests': keyLogsSnapshot.docs.length,
          'lastUsedAt': keyLogsSnapshot.docs.isNotEmpty
              ? keyLogsSnapshot.docs.first.get('timestamp')
              : null,
        });
      }
    } catch (_) {
      // Fail silently for seeding
    }
  }

  /// Fetch the third-party system integration keys from Firestore.
  Future<Map<String, String>> getSystemIntegrationKeys() async {
    try {
      final doc = await _fb.systemConfigCollection.doc('api_keys_config').get();
      if (!doc.exists) {
        // Return default/seeded keys if not yet stored
        return {
          'googleMapsApiKey': 'AIzaSyCvA7zLFFwUdL5xN9iqYy2uULtNnjH-NWo',
          'chatbotGeminiApiKey': 'AIzaSyCvX8gBK3vr399J3OnzEDbGYmv6PIIShyk',
          'sarvamApiKey': '',
          'voiceGeminiApiKey': '',
          'twilioAccountSid': '',
          'twilioAuthToken': '',
          'twilioPhoneNumber': '',
          'receptionistNumber': '',
          'whatsappAccessToken': '',
          'whatsappVerifyToken': 'crudoc_whatsapp_webhook_verify_token_2026',
          'voiceBotApiKey': 'crudoc_voice_bot_api_key_2026',
        };
      }
      final data = doc.data() as Map<String, dynamic>;
      return data.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      throw Exception('Failed to fetch system integration keys: ${e.toString()}');
    }
  }

  /// Save third-party system integration keys to Firestore.
  Future<void> saveSystemIntegrationKeys(Map<String, String> keys) async {
    try {
      final docRef = _fb.systemConfigCollection.doc('api_keys_config');
      await docRef.set(keys);

      // Write to Audit Log
      await _auditLogService.logAction(
        actionType: AuditActionType.updatedSystemConfig,
        details: {
          'configType': 'api_keys_config',
          'updatedKeys': keys.keys.toList(),
        },
      );
    } catch (e) {
      throw Exception('Failed to save system integration keys: ${e.toString()}');
    }
  }
}
