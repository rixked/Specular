import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:specular/backends/nextcloud/nextcloud_credentials.dart';
import 'package:specular/backends/nextcloud/webdav_backend.dart';
import 'package:specular/backends/storage_backend.dart';

final _credentials = NextcloudCredentials(
  server: Uri.parse('https://cloud.example.com'),
  loginName: 'alice@example.com',
  appPassword: 'super-secret-app-password',
);

const _root = '/remote.php/dav/files/alice@example.com';

/// A PROPFIND response as Nextcloud sends it, including the 404 propstat for
/// properties a collection doesn't have.
const _inboxListing =
    '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
 <d:response>
  <d:href>$_root/Specular/inbox/</d:href>
  <d:propstat>
   <d:prop>
    <d:resourcetype><d:collection/></d:resourcetype>
    <d:getetag>&quot;6553f1a2b3c4d&quot;</d:getetag>
    <d:getlastmodified>Mon, 16 Nov 2026 10:35:12 GMT</d:getlastmodified>
   </d:prop>
   <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
  <d:propstat>
   <d:prop><d:getcontentlength/></d:prop>
   <d:status>HTTP/1.1 404 Not Found</d:status>
  </d:propstat>
 </d:response>
 <d:response>
  <d:href>$_root/Specular/inbox/20261116T103512Z-a1b2c3-7f9e2d.json</d:href>
  <d:propstat>
   <d:prop>
    <d:resourcetype/>
    <d:getetag>&quot;e1&quot;</d:getetag>
    <d:getlastmodified>Mon, 16 Nov 2026 10:35:13 GMT</d:getlastmodified>
    <d:getcontentlength>212</d:getcontentlength>
   </d:prop>
   <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
 </d:response>
 <d:response>
  <d:href>$_root/Specular/inbox/100%25%20done%20%C3%A4.md</d:href>
  <d:propstat>
   <d:prop>
    <d:resourcetype/>
    <d:getetag>&quot;e2&quot;</d:getetag>
    <d:getlastmodified>Sun, 15 Nov 2026 08:00:00 GMT</d:getlastmodified>
    <d:getcontentlength>5</d:getcontentlength>
   </d:prop>
   <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
 </d:response>
 <d:response>
  <d:href>$_root/Specular/inbox/sub/</d:href>
  <d:propstat>
   <d:prop>
    <d:resourcetype><d:collection/></d:resourcetype>
    <d:getetag>&quot;e3&quot;</d:getetag>
   </d:prop>
   <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
 </d:response>
</d:multistatus>''';

/// Records requests and answers with [handler].
({NextcloudWebDavBackend backend, List<http.Request> requests}) _backend(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  final backend = NextcloudWebDavBackend(
    credentials: _credentials,
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
  );
  return (backend: backend, requests: requests);
}

void main() {
  group('requests', () {
    test('target the WebDAV root and authenticate with Basic auth', () async {
      final t = _backend((_) async => http.Response.bytes([1, 2, 3], 200));

      final data = await t.backend.get('Specular/inbox/x.json');

      expect(data, [1, 2, 3]);
      final request = t.requests.single;
      expect(request.method, 'GET');
      expect(request.url.host, 'cloud.example.com');
      expect(request.url.pathSegments, [
        'remote.php', 'dav', 'files', 'alice@example.com', //
        'Specular', 'inbox', 'x.json',
      ]);
      expect(
        request.headers['Authorization'],
        _credentials.authorizationHeader,
      );
      expect(request.headers['User-Agent'], 'Specular');
    });

    test('percent-encode file names', () async {
      final t = _backend((_) async => http.Response('', 201));
      await t.backend.put('Notes/Ideas #1 (2).md', Uint8List(0));
      expect(t.requests.single.url.path, '$_root/Notes/Ideas%20%231%20(2).md');
    });
  });

  group('list', () {
    test('parses a Nextcloud PROPFIND response', () async {
      final t = _backend(
        (_) async => http.Response(
          _inboxListing,
          207,
          headers: {'date': 'Mon, 16 Nov 2026 12:00:00 GMT'},
        ),
      );

      final listing = await t.backend.list('Specular/inbox');

      final request = t.requests.single;
      expect(request.method, 'PROPFIND');
      expect(request.headers['Depth'], '1');
      expect(request.url.path, '$_root/Specular/inbox/');
      expect(request.body, contains('getlastmodified'));

      expect(listing.etag, '"6553f1a2b3c4d"');
      expect(listing.serverTime, DateTime.utc(2026, 11, 16, 12));
      expect(listing.entries.map((e) => e.name), [
        '20261116T103512Z-a1b2c3-7f9e2d.json',
        '100% done ä.md',
        'sub',
      ]);

      final item = listing.entries.first;
      expect(item.isDirectory, isFalse);
      expect(item.etag, '"e1"');
      expect(item.lastModified, DateTime.utc(2026, 11, 16, 10, 35, 13));
      expect(item.size, 212);

      expect(listing.entries.last.isDirectory, isTrue);
    });

    test('a missing directory is StorageNotFoundException', () async {
      final t = _backend((_) async => http.Response('', 404));
      await expectLater(
        t.backend.list('Specular/inbox'),
        throwsA(isA<StorageNotFoundException>()),
      );
    });

    test('malformed XML is StorageProtocolException', () async {
      final t = _backend((_) async => http.Response('<d:multistatus', 207));
      await expectLater(
        t.backend.list('Specular/inbox'),
        throwsA(isA<StorageProtocolException>()),
      );
    });
  });

  group('put', () {
    test('uses If-None-Match: * when not overwriting', () async {
      final t = _backend((_) async => http.Response('', 201));
      await t.backend.put(
        'Specular/inbox/a.json',
        utf8.encode('{}'),
        overwrite: false,
      );
      final request = t.requests.single;
      expect(request.method, 'PUT');
      expect(request.headers['If-None-Match'], '*');
      expect(request.body, '{}');
    });

    test('overwriting sends no precondition', () async {
      final t = _backend((_) async => http.Response('', 204));
      await t.backend.put('Specular/devices/a.json', Uint8List(0));
      expect(t.requests.single.headers.containsKey('If-None-Match'), isFalse);
    });

    test('412 means the file already exists', () async {
      final t = _backend((_) async => http.Response('', 412));
      await expectLater(
        t.backend.put('x', Uint8List(0), overwrite: false),
        throwsA(isA<StorageAlreadyExistsException>()),
      );
    });

    test('409 means the parent directory is missing', () async {
      final t = _backend((_) async => http.Response('', 409));
      await expectLater(
        t.backend.put('Specular/inbox/a.json', Uint8List(0)),
        throwsA(isA<StorageNotFoundException>()),
      );
    });
  });

  group('delete and move', () {
    test('delete succeeds on 204 and reports 404 as not found', () async {
      final statuses = [204, 404];
      final t = _backend((_) async => http.Response('', statuses.removeAt(0)));
      await t.backend.delete('Specular/inbox/a.json');
      await expectLater(
        t.backend.delete('Specular/inbox/a.json'),
        throwsA(isA<StorageNotFoundException>()),
      );
      expect(t.requests.first.method, 'DELETE');
    });

    test('move sends an absolute Destination and Overwrite: F', () async {
      final t = _backend((_) async => http.Response('', 201));
      await t.backend.move('Specular/inbox/a.json', 'Notes/A note.md');
      final request = t.requests.single;
      expect(request.method, 'MOVE');
      expect(
        request.headers['Destination'],
        'https://cloud.example.com$_root/Notes/A%20note.md',
      );
      expect(request.headers['Overwrite'], 'F');
    });
  });

  group('ensureDirectory', () {
    test('treats 405 (exists) as success', () async {
      final t = _backend((_) async => http.Response('', 405));
      await t.backend.ensureDirectory('Specular');
      expect(t.requests.single.method, 'MKCOL');
      expect(t.requests.single.url.path, '$_root/Specular/');
    });

    test('creates missing parents on 409', () async {
      final existing = <String>{};
      final t = _backend((request) async {
        final segments = request.url.pathSegments.where((s) => s.isNotEmpty);
        final path = segments.skip(4).join('/');
        final parent = path.contains('/')
            ? path.substring(0, path.lastIndexOf('/'))
            : '';
        if (existing.contains(path)) return http.Response('', 405);
        if (parent.isNotEmpty && !existing.contains(parent)) {
          return http.Response('', 409);
        }
        existing.add(path);
        return http.Response('', 201);
      });

      await t.backend.ensureDirectory('Specular/inbox');

      expect(existing, {'Specular', 'Specular/inbox'});
    });
  });

  group('errors', () {
    test('401 means the app password was revoked', () async {
      final t = _backend((_) async => http.Response('', 401));
      await expectLater(
        t.backend.get('a'),
        throwsA(isA<StorageUnauthorizedException>()),
      );
    });

    test('5xx, 429 and network failures mean try again later', () async {
      for (final status in [500, 502, 503, 429]) {
        final t = _backend((_) async => http.Response('', status));
        await expectLater(
          t.backend.get('a'),
          throwsA(isA<StorageUnavailableException>()),
          reason: 'HTTP $status',
        );
      }
      final offline = _backend(
        (_) async => throw http.ClientException('Connection refused'),
      );
      await expectLater(
        offline.backend.get('a'),
        throwsA(isA<StorageUnavailableException>()),
      );
    });

    test('error messages never contain credentials', () async {
      for (final status in [401, 403, 404, 500]) {
        final t = _backend((_) async => http.Response('', status));
        try {
          await t.backend.get('Specular/inbox/a.json');
          fail('expected an exception');
        } on StorageException catch (e) {
          expect('$e', isNot(contains('super-secret')));
          expect('$e', isNot(contains(_credentials.authorizationHeader)));
        }
      }
    });
  });
}
