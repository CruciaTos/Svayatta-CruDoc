// The callable protocol as CallableClient reads it on Windows, where the
// cloud_functions plugin doesn't exist.
import 'package:doctor_management_app/core/services/callable_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns the result of a successful call', () {
    expect(CallableClient.decodeResponse(200, '{"result":{"matches":[1]}}'), {
      'matches': [1],
    });
  });

  test('turns a callable error into its code and message', () {
    expect(
      () => CallableClient.decodeResponse(
        403,
        '{"error":{"message":"Missing required permission","status":"PERMISSION_DENIED"}}',
      ),
      throwsA(
        isA<CallableException>()
            .having((e) => e.code, 'code', 'permission-denied')
            .having((e) => e.message, 'message', 'Missing required permission'),
      ),
    );
    expect(
      () => CallableClient.decodeResponse(
        401,
        '{"error":{"message":"Authentication required.","status":"UNAUTHENTICATED"}}',
      ),
      throwsA(
        isA<CallableException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
  });

  test('a missing function or a non-JSON reply is still an error', () {
    expect(
      () => CallableClient.decodeResponse(404, 'Function does not exist'),
      throwsA(
        isA<CallableException>().having((e) => e.code, 'code', 'not-found'),
      ),
    );
    expect(
      () => CallableClient.decodeResponse(500, '<html>'),
      throwsA(
        isA<CallableException>().having((e) => e.code, 'code', 'internal'),
      ),
    );
  });
}
