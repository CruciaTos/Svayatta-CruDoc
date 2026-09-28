import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:doctor_management_app/features/radiology/services/rvg_sensor_service.dart';

void main() {
  group('RvgSensorService', () {
    test('lists devices correctly from bridge response', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.url.path == '/devices') {
          return http.Response(
            jsonEncode({
              'devices': [
                'Vatech EzSensor Classic',
                'Virtual Dental RVG Simulator',
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = RvgSensorService(
        baseUrl: 'http://127.0.0.1:8766',
        httpClient: mockClient,
      );

      final devices = await service.listDevices();
      expect(devices.length, 2);
      expect(devices[0].name, 'Vatech EzSensor Classic');
      expect(devices[0].isSimulator, false);
      expect(devices[1].name, 'Virtual Dental RVG Simulator');
      expect(devices[1].isSimulator, true);
    });

    test('arms sensor and posts tooth metadata', () async {
      var armPosted = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.url.path == '/arm') {
          armPosted = true;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['tooth'], 36);
          expect(body['device'], 'Vatech EzSensor Classic');
          return http.Response(
            jsonEncode({'ok': true, 'status': 'arming'}),
            200,
          );
        }
        if (request.url.path == '/status') {
          return http.Response(
            jsonEncode({
              'state': 'armed',
              'message': 'Sensor armed. Waiting for exposure...',
              'elapsed': 2,
              'tooth': 36,
              'has_image': false,
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = RvgSensorService(
        baseUrl: 'http://127.0.0.1:8766',
        httpClient: mockClient,
      );

      final success = await service.armSensor(
        deviceName: 'Vatech EzSensor Classic',
        toothNumber: 36,
        patientName: 'Test Patient',
      );

      expect(success, true);
      expect(armPosted, true);
    });

    test('synthesizes valid periapical image on fallback', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Offline', 500);
      });

      final service = RvgSensorService(
        baseUrl: 'http://127.0.0.1:8766',
        httpClient: mockClient,
      );

      final result = await service.fetchLatestImage(
        toothNumber: 36,
        deviceName: 'Fallback Dental Sensor',
      );

      expect(result, isNotNull);
      expect(result!.tooth, 36);
      expect(result.width, 1200);
      expect(result.height, 1600);
      expect(result.imageBytes.isNotEmpty, true);
      // Valid PNG header: 0x89, 0x50, 0x4E, 0x47
      expect(result.imageBytes[0], 0x89);
      expect(result.imageBytes[1], 0x50);
      expect(result.imageBytes[2], 0x4E);
      expect(result.imageBytes[3], 0x47);
    });
  });
}
