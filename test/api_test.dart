import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yardline_worker/services.dart';

import 'support.dart';

void main() {
  test(
    'demo session retains HttpOnly operator cookie for subsequent requests',
    () async {
      final adapter = StubAdapter(
        (o) => o.path == '/api/session'
            ? jsonBody(
                {'ok': true},
                200,
                headers: {
                  'set-cookie': [
                    'yardline_role=operator; Path=/; HttpOnly; Secure; SameSite=Lax',
                  ],
                },
              )
            : jsonBody(fixture(), 200),
      );
      final api = HttpYardApi(
        const AppConfig(),
        client: Dio()..httpClientAdapter = adapter,
      );
      await api.operatorSession();
      final s = await api.state(null);
      expect(s.actor['role'], 'operator');
      expect(
        adapter.requests.last.headers['cookie'].toString(),
        contains('yardline_role=operator'),
      );
    },
  );
  test(
    'rejects demo fallback administrator and mismatched auth modes',
    () async {
      final raw = fixture();
      raw['actor']['role'] = 'administrator';
      final api = HttpYardApi(
        const AppConfig(),
        client: Dio()
          ..httpClientAdapter = StubAdapter((_) => jsonBody(raw, 200)),
      );
      await expectLater(
        api.state(null),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'SESSION_MISMATCH'),
        ),
      );
      raw['authMode'] = 'supabase';
      await expectLater(
        api.state(null),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'AUTH_MODE_MISMATCH'),
        ),
      );
    },
  );
  test(
    'bearer token read at request time and response stays bare Snapshot',
    () async {
      final raw = fixture()..['authMode'] = 'supabase';
      String token = 'token-one';
      final adapter = StubAdapter((_) => jsonBody(raw, 200));
      final api = HttpYardApi(
        const AppConfig(authMode: 'supabase'),
        client: Dio()..httpClientAdapter = adapter,
        token: () => token,
      );
      await api.state('yard-a');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer token-one',
      );
      token = 'token-two';
      await api.state('yard-a');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer token-two',
      );
      expect(adapter.requests.last.queryParameters, {'yard': 'yard-a'});
    },
  );
  test(
    'mutation keeps null expectedSlotId and reads full state envelope',
    () async {
      final adapter = StubAdapter(
        (_) => jsonBody({'state': fixture(), 'entityId': null}, 200),
      );
      final api = HttpYardApi(
        const AppConfig(),
        client: Dio()..httpClientAdapter = adapter,
      );
      final result = await api.action('move', {
        'yardId': 'yard-a',
        'containerId': 'c1',
        'slotId': 's3',
        'expectedSlotId': null,
        'physicalConfirmed': true,
      });
      expect(result.containsKey('state'), isTrue);
      expect(adapter.requests.single.path, '/api/actions/move');
      expect(
        (adapter.requests.single.data as Map).containsKey('expectedSlotId'),
        isTrue,
      );
    },
  );
  test(
    '409 is definite; transport or 503 write outcome is uncertain',
    () async {
      var status = 409;
      final api = HttpYardApi(
        const AppConfig(),
        client: Dio()
          ..httpClientAdapter = StubAdapter(
            (_) => jsonBody({
              'error': {
                'code': 'SLOT_OCCUPIED',
                'message': 'Choose another position.',
              },
            }, status),
          ),
      );
      await expectLater(
        api.action('move', {}),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.uncertain, 'uncertain', false)
              .having((e) => e.code, 'code', 'SLOT_OCCUPIED'),
        ),
      );
      status = 503;
      await expectLater(
        api.action('move', {}),
        throwsA(
          isA<ApiFailure>().having((e) => e.uncertain, 'uncertain', true),
        ),
      );
      final offline = HttpYardApi(
        const AppConfig(),
        client: Dio()
          ..httpClientAdapter = StubAdapter(
            (o) => throw DioException.connectionError(
              requestOptions: o,
              reason: 'offline',
            ),
          ),
      );
      await expectLater(
        offline.action('register', {}),
        throwsA(
          isA<ApiFailure>().having((e) => e.uncertain, 'uncertain', true),
        ),
      );
    },
  );
  test('rejects insecure or credential-bearing origins', () {
    expect(
      () => const AppConfig(baseUrl: 'http://example.com').validate(),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () =>
          const AppConfig(baseUrl: 'https://user:secret@example.com')
              .validate(),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => const AppConfig(baseUrl: 'https://example.com/api').validate(),
      throwsA(isA<ApiFailure>()),
    );
  });
}
