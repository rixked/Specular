import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

/// The platforms Specular ships release assets for (SPEC.md §3.6).
enum UpdatePlatform {
  android,
  windows,
  linux;

  /// Whether the app can download and install the update itself. On Linux
  /// it only notifies: the package manager owns the installed files.
  bool get installsInApp => this != linux;
}

/// One downloadable file of a release.
final class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size});

  final String name;
  final Uri url;
  final int? size;
}

/// A published GitHub Release.
final class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  final Version version;

  /// Release notes (Markdown).
  final String notes;

  /// The release's page on GitHub.
  final Uri pageUrl;
  final List<ReleaseAsset> assets;

  ReleaseAsset? asset(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  /// The installer or archive for [platform], if this release has one.
  ReleaseAsset? assetFor(UpdatePlatform platform) =>
      asset(releaseAssetName(platform, version));

  ReleaseAsset? get checksums => asset(checksumsAssetName);
}

const checksumsAssetName = 'SHA256SUMS';

/// The fixed asset names from SPEC.md §3.6.
String releaseAssetName(UpdatePlatform platform, Version version) =>
    switch (platform) {
      UpdatePlatform.android => 'specular-$version-android.apk',
      UpdatePlatform.windows => 'specular-$version-windows-setup.exe',
      UpdatePlatform.linux => 'specular-$version-linux-x64.tar.gz',
    };

/// Reads a release from the GitHub API (`/releases/latest`).
///
/// Returns null for drafts, pre-releases, tags that are not `vX.Y.Z`, or
/// anything malformed, so a bad release is ignored instead of crashing.
ReleaseInfo? parseRelease(Object? json) {
  if (json is! Map<String, Object?>) return null;
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = json['tag_name'];
  final page = json['html_url'];
  if (tag is! String || page is! String || !tag.startsWith('v')) return null;

  final Version version;
  try {
    version = Version.parse(tag.substring(1));
  } on FormatException {
    return null;
  }
  if (version.isPreRelease) return null;

  final assets = <ReleaseAsset>[];
  final rawAssets = json['assets'];
  if (rawAssets is List) {
    for (final raw in rawAssets) {
      if (raw is! Map<String, Object?>) continue;
      final name = raw['name'];
      final url = raw['browser_download_url'];
      final parsedUrl = url is String ? Uri.tryParse(url) : null;
      if (name is! String || parsedUrl == null || parsedUrl.scheme != 'https') {
        continue;
      }
      final size = raw['size'];
      assets.add(
        ReleaseAsset(
          name: name,
          url: parsedUrl,
          size: size is int ? size : null,
        ),
      );
    }
  }

  final body = json['body'];
  return ReleaseInfo(
    version: version,
    notes: body is String ? body : '',
    pageUrl: Uri.parse(page),
    assets: List.unmodifiable(assets),
  );
}

/// Whether [latest] should be offered over [current].
bool isNewerRelease(Version latest, Version current) => latest > current;

/// Parses `sha256sum` output: `<64 hex>  <file name>` per line (a `*`
/// before the name marks binary mode). Returns file name → lower-case hash.
Map<String, String> parseSha256Sums(String text) {
  final sums = <String, String>{};
  final line = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$');
  for (final raw in text.split('\n')) {
    final match = line.firstMatch(raw.trimRight());
    if (match == null) continue;
    sums[match.group(2)!.trim()] = match.group(1)!.toLowerCase();
  }
  return sums;
}

/// SHA-256 of [bytes] as lower-case hex.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
