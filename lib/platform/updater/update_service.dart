import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../core/updates/releases.dart';

export '../../core/updates/update_settings.dart';

/// The result of an update check.
sealed class UpdateCheck {
  const UpdateCheck();
}

final class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.release);
  final ReleaseInfo release;
}

final class UpToDate extends UpdateCheck {
  const UpToDate();
}

final class UpdateCheckFailed extends UpdateCheck {
  const UpdateCheckFailed(this.message);
  final String message;
}

/// What happened when the update was handed to the platform.
enum InstallOutcome {
  /// The installer runs; on Windows the app should quit now.
  started,

  /// Android: the user must first allow "Install unknown apps" for
  /// Specular; the settings page was opened.
  needsPermission,
}

/// The download did not match `SHA256SUMS` and was deleted.
final class UpdateVerificationException implements Exception {
  const UpdateVerificationException(this.message);
  final String message;

  @override
  String toString() => 'UpdateVerificationException: $message';
}

/// Checks GitHub Releases for a newer Specular, downloads it, verifies its
/// SHA-256 and hands it to the platform's installer (SPEC.md §3.6).
///
/// Privacy (SPEC.md §8): the only request is an anonymous GET of public
/// release metadata. No device ID, Nextcloud URL or other user data is sent;
/// the User-Agent is `Specular/<version>`.
final class UpdateService {
  UpdateService({
    required this.currentVersion,
    required this.platform,
    http.Client? client,
    this.repository = 'rixked/Specular',
    Future<Directory> Function()? downloadDirectory,
    MethodChannel? channel,
  }) : _client = client ?? http.Client(),
       _downloadDirectory = downloadDirectory ?? getTemporaryDirectory,
       _channel = channel ?? const MethodChannel('de.rixk.specular/updates');

  final Version currentVersion;
  final UpdatePlatform platform;

  /// `owner/name` on GitHub.
  final String repository;
  final http.Client _client;
  final Future<Directory> Function() _downloadDirectory;
  final MethodChannel _channel;

  Map<String, String> get _headers => {
    'User-Agent': 'Specular/$currentVersion',
    'Accept': 'application/vnd.github+json',
  };

  Uri get _latestUrl =>
      Uri.parse('https://api.github.com/repos/$repository/releases/latest');

  Future<UpdateCheck> check() async {
    try {
      final response = await _client
          .get(_latestUrl, headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) return const UpToDate(); // No release.
      if (response.statusCode != 200) {
        return UpdateCheckFailed('GitHub answered HTTP ${response.statusCode}');
      }
      final release = parseRelease(jsonDecode(response.body));
      if (release == null || !isNewerRelease(release.version, currentVersion)) {
        return const UpToDate();
      }
      return UpdateAvailable(release);
    } on TimeoutException {
      return const UpdateCheckFailed('GitHub did not answer in time');
    } on http.ClientException {
      return const UpdateCheckFailed('No connection to GitHub');
    } on FormatException {
      return const UpdateCheckFailed('Unexpected answer from GitHub');
    }
  }

  /// Downloads this platform's asset and verifies it against `SHA256SUMS`.
  ///
  /// [onProgress] gets values from 0 to 1 when the size is known.
  Future<File> download(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    final asset = release.assetFor(platform);
    final sumsAsset = release.checksums;
    if (asset == null || sumsAsset == null) {
      throw const UpdateVerificationException(
        'This release has no installer for this device.',
      );
    }

    final sumsResponse = await _client.get(sumsAsset.url, headers: _headers);
    if (sumsResponse.statusCode != 200) {
      throw http.ClientException('Could not download SHA256SUMS');
    }
    final expected = parseSha256Sums(sumsResponse.body)[asset.name];
    if (expected == null) {
      throw const UpdateVerificationException(
        'SHA256SUMS does not list the installer.',
      );
    }

    final dir = Directory('${(await _downloadDirectory()).path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${asset.name}');

    final request = http.Request('GET', asset.url)..headers.addAll(_headers);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Download failed (HTTP ${response.statusCode})',
      );
    }
    final total = response.contentLength ?? asset.size;
    final sink = file.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
      hasher.close();
    }

    if (digestSink.value.toString() != expected) {
      await file.delete();
      throw const UpdateVerificationException(
        'The download does not match its checksum and was deleted.',
      );
    }
    return file;
  }

  /// Hands the verified file to the installer.
  Future<InstallOutcome> install(File file) async {
    switch (platform) {
      case UpdatePlatform.android:
        final result = await _channel.invokeMethod<String>('installApk', {
          'path': file.path,
        });
        return result == 'permission'
            ? InstallOutcome.needsPermission
            : InstallOutcome.started;
      case UpdatePlatform.windows:
        // The installer closes this app, replaces it and starts it again.
        await Process.start(file.path, const [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
        ], mode: ProcessStartMode.detached);
        return InstallOutcome.started;
      case UpdatePlatform.linux:
        throw UnsupportedError('Linux updates come from the package manager');
    }
  }

  void close() => _client.close();
}

/// Collects the result of a chunked SHA-256 conversion.
final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// The update platform of this device, or null where Specular has no
/// releases (for example macOS).
UpdatePlatform? currentUpdatePlatform() {
  if (Platform.isAndroid) return UpdatePlatform.android;
  if (Platform.isWindows) return UpdatePlatform.windows;
  if (Platform.isLinux) return UpdatePlatform.linux;
  return null;
}
