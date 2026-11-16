import 'dart:convert';

/// The result of a successful login: everything needed to talk to the
/// user's Nextcloud.
///
/// [toString] never includes the app password, so credentials can't leak
/// into logs by accident (SPEC.md §8).
final class NextcloudCredentials {
  const NextcloudCredentials({
    required this.server,
    required this.loginName,
    required this.appPassword,
  });

  factory NextcloudCredentials.fromJson(Map<String, Object?> json) {
    final server = json['server'];
    final loginName = json['loginName'];
    final appPassword = json['appPassword'];
    if (server is! String || loginName is! String || appPassword is! String) {
      throw const FormatException('Incomplete Nextcloud credentials');
    }
    return NextcloudCredentials(
      server: normalizeServerUrl(server),
      loginName: loginName,
      appPassword: appPassword,
    );
  }

  /// Base URL of the Nextcloud instance, always HTTPS, without trailing
  /// slash, for example `https://cloud.example.com` or
  /// `https://example.com/nextcloud`.
  final Uri server;
  final String loginName;
  final String appPassword;

  /// The user's WebDAV root: `{server}/remote.php/dav/files/{loginName}/`.
  Uri get webDavRoot => server.replace(
    pathSegments: [
      ...server.pathSegments.where((s) => s.isNotEmpty),
      'remote.php',
      'dav',
      'files',
      loginName,
      '',
    ],
  );

  /// The value of the HTTP `Authorization` header.
  String get authorizationHeader =>
      'Basic ${base64.encode(utf8.encode('$loginName:$appPassword'))}';

  Map<String, Object?> toJson() => {
    'server': server.toString(),
    'loginName': loginName,
    'appPassword': appPassword,
  };

  @override
  String toString() => 'NextcloudCredentials($loginName @ $server)';
}

/// Thrown when the user enters a server address Specular won't use.
final class InvalidServerUrlException implements Exception {
  const InvalidServerUrlException(this.message);

  final String message;

  @override
  String toString() => 'InvalidServerUrlException: $message';
}

/// Turns what the user typed into a canonical server URL.
///
/// - `cloud.example.com` becomes `https://cloud.example.com`.
/// - Trailing slashes, `/index.php`, `/login`, query and fragment are removed.
/// - `http://` is rejected: HTTPS is required (SPEC.md §8).
Uri normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) {
    throw const InvalidServerUrlException('Enter your Nextcloud address.');
  }
  if (!text.contains('://')) text = 'https://$text';

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw InvalidServerUrlException('"$input" is not a valid address.');
  }
  if (uri.scheme == 'http') {
    throw const InvalidServerUrlException(
      'Specular only connects over HTTPS. Use an https:// address.',
    );
  }
  if (uri.scheme != 'https') {
    throw InvalidServerUrlException('Unsupported scheme "${uri.scheme}".');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const InvalidServerUrlException(
      'Do not put a user name or password into the address.',
    );
  }

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  const strip = {'index.php', 'login', 'apps', 'remote.php'};
  final cut = segments.indexWhere(strip.contains);
  final path = cut < 0 ? segments : segments.sublist(0, cut);

  return Uri(
    scheme: 'https',
    host: uri.host.toLowerCase(),
    port: uri.hasPort && uri.port != 443 ? uri.port : null,
    pathSegments: path.isEmpty ? null : path,
  );
}
