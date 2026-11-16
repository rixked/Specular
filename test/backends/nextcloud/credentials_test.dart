import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specular/backends/nextcloud/credential_store.dart';
import 'package:specular/backends/nextcloud/nextcloud_credentials.dart';

void main() {
  group('normalizeServerUrl', () {
    test('adds https:// and strips noise', () {
      expect(
        normalizeServerUrl('cloud.example.com').toString(),
        'https://cloud.example.com',
      );
      expect(
        normalizeServerUrl('  https://Cloud.Example.com/  ').toString(),
        'https://cloud.example.com',
      );
      expect(
        normalizeServerUrl('https://cloud.example.com/index.php/login?x=1#y')
            .toString(),
        'https://cloud.example.com',
      );
      expect(
        normalizeServerUrl('https://cloud.example.com/apps/files/').toString(),
        'https://cloud.example.com',
      );
    });

    test('keeps subdirectory installs and custom ports', () {
      expect(
        normalizeServerUrl('example.com/nextcloud/').toString(),
        'https://example.com/nextcloud',
      );
      expect(
        normalizeServerUrl('https://example.com:8443').toString(),
        'https://example.com:8443',
      );
      expect(
        normalizeServerUrl('https://example.com:443').toString(),
        'https://example.com',
      );
    });

    test('requires HTTPS (SPEC.md §8)', () {
      expect(
        () => normalizeServerUrl('http://cloud.example.com'),
        throwsA(isA<InvalidServerUrlException>()),
      );
      expect(
        () => normalizeServerUrl('ftp://cloud.example.com'),
        throwsA(isA<InvalidServerUrlException>()),
      );
    });

    test('rejects empty input and embedded credentials', () {
      expect(
        () => normalizeServerUrl('   '),
        throwsA(isA<InvalidServerUrlException>()),
      );
      expect(
        () => normalizeServerUrl('https://bob:secret@cloud.example.com'),
        throwsA(isA<InvalidServerUrlException>()),
      );
    });
  });

  group('NextcloudCredentials', () {
    final credentials = NextcloudCredentials(
      server: Uri.parse('https://example.com/nextcloud'),
      loginName: 'alice@example.com',
      appPassword: 's3cr3t-app-password',
    );

    test('builds the WebDAV root', () {
      final root = credentials.webDavRoot;
      expect(root.scheme, 'https');
      expect(root.host, 'example.com');
      expect(root.pathSegments, [
        'nextcloud', 'remote.php', 'dav', 'files', 'alice@example.com', '', //
      ]);
    });

    test('builds a Basic auth header', () {
      expect(
        credentials.authorizationHeader,
        'Basic ${base64.encode(utf8.encode('alice@example.com:s3cr3t-app-password'))}',
      );
    });

    test('never prints the app password', () {
      expect(credentials.toString(), isNot(contains('s3cr3t')));
      expect('$credentials', contains('alice@example.com'));
    });

    test('round-trips through JSON', () {
      final copy = NextcloudCredentials.fromJson(credentials.toJson());
      expect(copy.server, credentials.server);
      expect(copy.loginName, credentials.loginName);
      expect(copy.appPassword, credentials.appPassword);
    });

    test('rejects incomplete JSON', () {
      expect(
        () => NextcloudCredentials.fromJson({'server': 'https://a.b'}),
        throwsFormatException,
      );
    });
  });

  test('InMemoryCredentialStore', () async {
    final store = InMemoryCredentialStore();
    expect(await store.read(), isNull);
    final c = NextcloudCredentials(
      server: Uri.parse('https://a.example'),
      loginName: 'a',
      appPassword: 'p',
    );
    await store.write(c);
    expect(await store.read(), same(c));
    await store.clear();
    expect(await store.read(), isNull);
  });
}
