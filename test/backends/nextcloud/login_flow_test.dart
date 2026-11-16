import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:specular/backends/nextcloud/login_flow.dart';
import 'package:specular/backends/storage_backend.dart';

const _startResponse = {
  'poll': {
    'token': 'poll-token-123',
    'endpoint': 'https://cloud.example.com/login/v2/poll',
  },
  'login': 'https://cloud.example.com/login/v2/flow/abc',
};

const _granted = {
  'server': 'https://cloud.example.com',
  'loginName': 'alice',
  'appPassword': 'generated-app-password',
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('start', () {
    test('POSTs to /index.php/login/v2 and identifies as Specular', () async {
      late http.Request seen;
      final flow = NextcloudLoginFlow(
        clientName: 'Specular (Pixel)',
        client: MockClient((request) async {
          seen = request;
          return _json(_startResponse);
        }),
      );

      final session = await flow.start('cloud.example.com/');

      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        'https://cloud.example.com/index.php/login/v2',
      );
      expect(seen.headers['User-Agent'], 'Specular (Pixel)');
      expect(
        session.loginUrl.toString(),
        'https://cloud.example.com/login/v2/flow/abc',
      );
      expect(
        session.pollEndpoint.toString(),
        'https://cloud.example.com/login/v2/poll',
      );
      expect(session.pollToken, 'poll-token-123');
    });

    test('works for subdirectory installs', () async {
      late Uri url;
      final flow = NextcloudLoginFlow(
        client: MockClient((request) async {
          url = request.url;
          return _json(_startResponse);
        }),
      );
      await flow.start('https://example.com/nextcloud');
      expect(
        url.toString(),
        'https://example.com/nextcloud/index.php/login/v2',
      );
    });

    test('rejects a server that hands out non-HTTPS URLs', () async {
      final flow = NextcloudLoginFlow(
        client: MockClient(
          (_) async => _json({
            'poll': {
              'token': 't',
              'endpoint': 'http://cloud.example.com/login/v2/poll',
            },
            'login': 'https://cloud.example.com/login/v2/flow/abc',
          }),
        ),
      );
      await expectLater(
        flow.start('cloud.example.com'),
        throwsA(isA<StorageProtocolException>()),
      );
    });

    test('reports non-Nextcloud servers clearly', () async {
      final flow = NextcloudLoginFlow(
        client: MockClient((_) async => http.Response('<html>', 404)),
      );
      await expectLater(
        flow.start('example.com'),
        throwsA(isA<StorageProtocolException>()),
      );
    });
  });

  group('poll', () {
    final session = LoginFlowSession(
      loginUrl: Uri.parse('https://cloud.example.com/login/v2/flow/abc'),
      pollEndpoint: Uri.parse('https://cloud.example.com/login/v2/poll'),
      pollToken: 'poll-token-123',
    );

    test('returns null while pending and credentials once approved', () async {
      var calls = 0;
      final bodies = <String>[];
      final flow = NextcloudLoginFlow(
        client: MockClient((request) async {
          bodies.add(request.body);
          return ++calls < 3 ? http.Response('', 404) : _json(_granted);
        }),
      );

      expect(await flow.poll(session), isNull);
      expect(await flow.poll(session), isNull);
      final credentials = await flow.poll(session);

      expect(credentials!.loginName, 'alice');
      expect(credentials.appPassword, 'generated-app-password');
      expect(credentials.server.toString(), 'https://cloud.example.com');
      expect(bodies.first, 'token=poll-token-123');
    });

    test(
      'waitForCredentials polls until approved, riding out outages',
      () async {
        final responses = [
          http.Response('', 404),
          http.Response('', 503),
          http.Response('', 404),
          _json(_granted),
        ];
        final delays = <Duration>[];
        final flow = NextcloudLoginFlow(
          client: MockClient((_) async => responses.removeAt(0)),
          delay: (d) async => delays.add(d),
        );

        final credentials = await flow.waitForCredentials(session);

        expect(credentials.loginName, 'alice');
        expect(delays, hasLength(3));
      },
    );

    test('waitForCredentials gives up after the timeout', () async {
      final flow = NextcloudLoginFlow(
        client: MockClient((_) async => http.Response('', 404)),
        delay: (_) async {},
      );
      await expectLater(
        flow.waitForCredentials(
          session,
          interval: const Duration(seconds: 2),
          timeout: const Duration(seconds: 10),
        ),
        throwsA(isA<LoginFlowCancelledException>()),
      );
    });

    test('waitForCredentials can be cancelled', () async {
      final cancel = Completer<void>();
      var polls = 0;
      final flow = NextcloudLoginFlow(
        client: MockClient((_) async {
          if (++polls == 2) cancel.complete();
          return http.Response('', 404);
        }),
        delay: (_) => Future<void>.delayed(Duration.zero),
      );
      await expectLater(
        flow.waitForCredentials(session, cancel: cancel.future),
        throwsA(isA<LoginFlowCancelledException>()),
      );
      expect(polls, lessThanOrEqualTo(3));
    });

    test('rejects granted credentials for a non-HTTPS server', () async {
      final flow = NextcloudLoginFlow(
        client: MockClient(
          (_) async =>
              _json({..._granted, 'server': 'http://cloud.example.com'}),
        ),
      );
      await expectLater(
        flow.poll(session),
        throwsA(isA<StorageProtocolException>()),
      );
    });
  });
}
