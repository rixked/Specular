import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:specular/backends/nextcloud/certificate_pinning.dart';
import 'package:specular/backends/nextcloud/nextcloud_credentials.dart';
import 'package:specular/backends/storage_backend.dart';

/// Fingerprint of test/fixtures/self_signed_cert.pem (see its README).
const _fixtureFingerprint =
    'A2:ED:3C:AF:26:CD:BD:4B:E5:88:2B:91:A7:71:51:CC:'
    '94:E0:69:B4:6E:F9:AA:56:09:E4:01:52:E3:7A:05:C1';

void main() {
  group('certificateFingerprint', () {
    test('is SHA-256 as upper-case hex pairs', () {
      // SHA-256 of no bytes.
      expect(
        certificateFingerprint(const []),
        'E3:B0:C4:42:98:FC:1C:14:9A:FB:F4:C8:99:6F:B9:24:'
        '27:AE:41:E4:64:9B:93:4C:A4:95:99:1B:78:52:B8:55',
      );
    });
  });

  group('isPinnedCertificate', () {
    test('only the pinned fingerprint for the same host', () {
      bool check(String fp, String host, String? pinned) => isPinnedCertificate(
        fingerprint: fp,
        host: host,
        expectedHost: 'cloud.example.com',
        pinnedFingerprint: pinned,
      );
      expect(check('AA', 'cloud.example.com', 'AA'), isTrue);
      expect(check('AA', 'Cloud.Example.com', 'AA'), isTrue);
      expect(check('AA', 'cloud.example.com', null), isFalse);
      expect(check('AA', 'cloud.example.com', 'BB'), isFalse);
      expect(check('AA', 'evil.example.com', 'AA'), isFalse);
    });
  });

  test('credentials keep the pinned fingerprint', () {
    final credentials = NextcloudCredentials(
      server: Uri.parse('https://cloud.example.com'),
      loginName: 'alice',
      appPassword: 'pw',
    ).withPinnedCertificate('AA:BB');
    final copy = NextcloudCredentials.fromJson(credentials.toJson());
    expect(copy.pinnedCertificate, 'AA:BB');
    expect(copy.appPassword, 'pw');
  });

  group('against a real self-signed HTTPS server', () {
    late HttpServer server;
    late Uri url;

    setUpAll(() async {
      final context = SecurityContext()
        ..useCertificateChain('test/fixtures/self_signed_cert.pem')
        ..usePrivateKey('test/fixtures/self_signed_key.pem');
      server = await HttpServer.bindSecure('localhost', 0, context);
      server.listen((request) {
        request.response
          ..statusCode = 200
          ..write('hello')
          ..close();
      });
      url = Uri.parse('https://localhost:${server.port}/');
    });

    tearDownAll(() => server.close(force: true));

    test('is never accepted silently: reports the fingerprint', () async {
      final client = PinningHttpClient(host: 'localhost');
      try {
        await client.get(url);
        fail('A self-signed certificate must not be accepted');
      } on StorageUntrustedCertificateException catch (e) {
        expect(e.host, 'localhost');
        expect(e.fingerprint, _fixtureFingerprint);
      } finally {
        client.close();
      }
    });

    test('works once that exact certificate is pinned', () async {
      final client = PinningHttpClient(
        host: 'localhost',
        pinnedFingerprint: _fixtureFingerprint,
      );
      final response = await client.get(url);
      expect(response.statusCode, 200);
      expect(response.body, 'hello');
      client.close();
    });

    test('a different pinned fingerprint is rejected', () async {
      final client = PinningHttpClient(
        host: 'localhost',
        pinnedFingerprint: 'AA:BB:CC',
      );
      await expectLater(
        client.get(url),
        throwsA(isA<StorageUntrustedCertificateException>()),
      );
      client.close();
    });

    test('a pin for another host does not apply', () async {
      final client = PinningHttpClient(
        host: 'cloud.example.com',
        pinnedFingerprint: _fixtureFingerprint,
      );
      await expectLater(
        client.get(url),
        throwsA(isA<StorageUntrustedCertificateException>()),
      );
      client.close();
    });

    test('unreachable servers still count as offline', () async {
      final client = PinningHttpClient(host: 'localhost');
      await expectLater(
        client.get(Uri.parse('https://localhost:1/')),
        throwsA(isA<http.ClientException>()),
      );
      client.close();
    });
  });
}
