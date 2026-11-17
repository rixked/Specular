import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:specular/core/updates/releases.dart';
import 'package:specular/platform/updater/update_service.dart';

const _apkBytes = [1, 2, 3, 4, 5];

/// A fake GitHub: the latest release and its assets.
MockClient fakeGitHub({
  String tag = 'v0.2.0',
  int status = 200,
  String? sums,
  List<int> apk = _apkBytes,
  List<http.BaseRequest>? requests,
}) {
  final base = 'https://github.com/rixked/Specular/releases/download/$tag';
  return MockClient((request) async {
    requests?.add(request);
    final url = request.url.toString();
    if (url.endsWith('/releases/latest')) {
      if (status != 200) return http.Response('', status);
      return http.Response(
        jsonEncode({
          'tag_name': tag,
          'html_url': 'https://github.com/rixked/Specular/releases/tag/$tag',
          'draft': false,
          'prerelease': false,
          'body': 'notes',
          'assets': [
            for (final name in ['specular-0.2.0-android.apk', 'SHA256SUMS'])
              {'name': name, 'browser_download_url': '$base/$name'},
          ],
        }),
        200,
      );
    }
    if (url.endsWith('/SHA256SUMS')) {
      return http.Response(
        sums ?? '${sha256Hex(_apkBytes)}  specular-0.2.0-android.apk\n',
        200,
      );
    }
    if (url.endsWith('.apk')) return http.Response.bytes(apk, 200);
    return http.Response('', 404);
  });
}

void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('upd'));
  tearDown(() async => temp.delete(recursive: true));

  UpdateService service(http.Client client, {String current = '0.1.0'}) =>
      UpdateService(
        currentVersion: Version.parse(current),
        platform: UpdatePlatform.android,
        client: client,
        downloadDirectory: () async => temp,
      );

  group('check', () {
    test('finds a newer release', () async {
      final result = await service(fakeGitHub()).check();
      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).release.version, Version(0, 2, 0));
    });

    test('is up to date on the same or an older release', () async {
      expect(
        await service(fakeGitHub(), current: '0.2.0').check(),
        isA<UpToDate>(),
      );
      expect(
        await service(fakeGitHub(), current: '0.3.0').check(),
        isA<UpToDate>(),
      );
    });

    test('no release yet (404) is not an error', () async {
      expect(await service(fakeGitHub(status: 404)).check(), isA<UpToDate>());
    });

    test('reports server and network problems', () async {
      expect(
        await service(fakeGitHub(status: 500)).check(),
        isA<UpdateCheckFailed>(),
      );
      final offline = MockClient(
        (_) async => throw http.ClientException('no network'),
      );
      expect(await service(offline).check(), isA<UpdateCheckFailed>());
    });

    test('is anonymous: only the app version in the User-Agent', () async {
      final requests = <http.BaseRequest>[];
      await service(fakeGitHub(requests: requests)).check();
      final request = requests.single;
      expect(
        request.url.toString(),
        'https://api.github.com/repos/rixked/Specular/releases/latest',
      );
      expect(request.headers['User-Agent'], 'Specular/0.1.0');
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(request.url.query, isEmpty);
    });
  });

  group('download', () {
    test('saves the installer when its checksum matches', () async {
      final updates = service(fakeGitHub());
      final release = (await updates.check() as UpdateAvailable).release;
      final progress = <double>[];

      final file = await updates.download(release, onProgress: progress.add);

      expect(await file.readAsBytes(), _apkBytes);
      expect(file.path, endsWith('specular-0.2.0-android.apk'));
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    });

    test('deletes a download whose checksum does not match', () async {
      final updates = service(fakeGitHub(apk: [9, 9, 9]));
      final release = (await updates.check() as UpdateAvailable).release;

      await expectLater(
        updates.download(release),
        throwsA(isA<UpdateVerificationException>()),
      );
      final leftovers = temp
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(leftovers, isEmpty);
    });

    test('refuses an installer that SHA256SUMS does not list', () async {
      final updates = service(fakeGitHub(sums: '${'0' * 64}  other.apk\n'));
      final release = (await updates.check() as UpdateAvailable).release;
      await expectLater(
        updates.download(release),
        throwsA(isA<UpdateVerificationException>()),
      );
    });
  });
}
