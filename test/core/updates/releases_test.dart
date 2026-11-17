import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:specular/core/updates/releases.dart';

Map<String, Object?> releaseJson({
  String tag = 'v0.2.0',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, Object?>>? assets,
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/rixked/Specular/releases/tag/$tag',
  'draft': draft,
  'prerelease': prerelease,
  'body': '## Changes\n- Media',
  'assets':
      assets ??
      [
        for (final name in [
          'specular-0.2.0-android.apk',
          'specular-0.2.0-windows-setup.exe',
          'specular-0.2.0-linux-x64.tar.gz',
          'SHA256SUMS',
        ])
          {
            'name': name,
            'browser_download_url':
                'https://github.com/rixked/Specular/releases/download/$tag/$name',
            'size': 1234,
          },
      ],
};

void main() {
  group('parseRelease', () {
    test('reads version, notes, page and assets', () {
      final release = parseRelease(releaseJson())!;
      expect(release.version, Version(0, 2, 0));
      expect(release.notes, contains('Media'));
      expect(release.pageUrl.host, 'github.com');
      expect(
        release.assetFor(UpdatePlatform.android)!.name,
        'specular-0.2.0-android.apk',
      );
      expect(
        release.assetFor(UpdatePlatform.windows)!.name,
        'specular-0.2.0-windows-setup.exe',
      );
      expect(release.checksums!.size, 1234);
    });

    test('ignores drafts, pre-releases and odd tags', () {
      expect(parseRelease(releaseJson(draft: true)), isNull);
      expect(parseRelease(releaseJson(prerelease: true)), isNull);
      expect(parseRelease(releaseJson(tag: 'v0.3.0-beta.1')), isNull);
      expect(parseRelease(releaseJson(tag: 'latest')), isNull);
      expect(parseRelease(releaseJson(tag: 'v1.x')), isNull);
      expect(parseRelease('not a map'), isNull);
    });

    test('drops assets that are not served over HTTPS', () {
      final release = parseRelease(
        releaseJson(
          assets: [
            {
              'name': 'specular-0.2.0-android.apk',
              'browser_download_url': 'http://evil.example/app.apk',
            },
          ],
        ),
      )!;
      expect(release.assets, isEmpty);
    });
  });

  test('version comparison is semantic, not alphabetical', () {
    expect(isNewerRelease(Version(0, 10, 0), Version(0, 9, 0)), isTrue);
    expect(isNewerRelease(Version(0, 1, 0), Version(0, 1, 0)), isFalse);
    expect(isNewerRelease(Version(0, 1, 0), Version(0, 2, 0)), isFalse);
  });

  test('Linux only notifies; Android and Windows install in the app', () {
    expect(UpdatePlatform.linux.installsInApp, isFalse);
    expect(UpdatePlatform.android.installsInApp, isTrue);
    expect(UpdatePlatform.windows.installsInApp, isTrue);
  });

  test('parseSha256Sums reads sha256sum output', () {
    final hash = 'A' * 64;
    final sums = parseSha256Sums(
      '${'0' * 64}  specular-0.2.0-android.apk\n'
      '$hash *specular-0.2.0-windows-setup.exe\n'
      'garbage line\n',
    );
    expect(sums['specular-0.2.0-android.apk'], '0' * 64);
    expect(sums['specular-0.2.0-windows-setup.exe'], 'a' * 64);
    expect(sums, hasLength(2));
  });

  test('sha256Hex', () {
    expect(
      sha256Hex(const []),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });
}
