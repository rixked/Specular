import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage_backend.dart';
import 'nextcloud_credentials.dart';

/// A started login: the URL to open in the browser and what to poll.
final class LoginFlowSession {
  const LoginFlowSession({
    required this.loginUrl,
    required this.pollEndpoint,
    required this.pollToken,
  });

  /// Open this in the system browser so the user can approve access.
  final Uri loginUrl;
  final Uri pollEndpoint;
  final String pollToken;

  @override
  String toString() => 'LoginFlowSession($loginUrl)';
}

/// The user did not approve the login in time, or the flow was cancelled.
final class LoginFlowCancelledException implements Exception {
  const LoginFlowCancelledException(this.message);

  final String message;

  @override
  String toString() => 'LoginFlowCancelledException: $message';
}

/// Nextcloud Login Flow v2 (SPEC.md §3.1).
///
/// 1. [start] asks the server for a login URL and a poll token.
/// 2. The app opens [LoginFlowSession.loginUrl] in the browser.
/// 3. [waitForCredentials] polls until the user approved, then returns the
///    app password. The user never types or copies a password.
///
/// Nextcloud names the new app password after the User-Agent, so the user
/// sees "Specular (Pixel)" under Settings → Security and can revoke it there.
final class NextcloudLoginFlow {
  NextcloudLoginFlow({
    http.Client? client,
    this.clientName = 'Specular',
    this.requestTimeout = const Duration(seconds: 20),
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _delay = delay ?? Future<void>.delayed;

  final http.Client _client;

  /// Shown as the app password's name in Nextcloud.
  final String clientName;
  final Duration requestTimeout;
  final Future<void> Function(Duration) _delay;

  Map<String, String> get _headers => {
    'User-Agent': clientName,
    'Accept': 'application/json',
    'OCS-APIRequest': 'true',
  };

  /// Starts a login on [serverInput], which is normalized with
  /// [normalizeServerUrl] (and must be HTTPS).
  Future<LoginFlowSession> start(String serverInput) async {
    final server = normalizeServerUrl(serverInput);
    final url = server.replace(
      pathSegments: [...server.pathSegments, 'index.php', 'login', 'v2'],
    );
    final response = await _send(() => _client.post(url, headers: _headers));
    if (response.statusCode != 200) {
      throw _unexpected(
        response,
        'Could not start the login. Is this a '
        'Nextcloud server?',
      );
    }
    final json = _decodeObject(response);
    final poll = json['poll'];
    final login = json['login'];
    if (poll is! Map<String, Object?> || login is! String) {
      throw const StorageProtocolException('Malformed login flow response');
    }
    final token = poll['token'];
    final endpoint = poll['endpoint'];
    if (token is! String || endpoint is! String) {
      throw const StorageProtocolException('Malformed login flow response');
    }
    return LoginFlowSession(
      loginUrl: _requireHttps(login),
      pollEndpoint: _requireHttps(endpoint),
      pollToken: token,
    );
  }

  /// Polls once. Returns the credentials once the user approved, or null
  /// while the approval is still pending.
  Future<NextcloudCredentials?> poll(LoginFlowSession session) async {
    final response = await _send(
      () => _client.post(
        session.pollEndpoint,
        headers: _headers,
        body: {'token': session.pollToken},
      ),
    );
    switch (response.statusCode) {
      case 200:
        try {
          return NextcloudCredentials.fromJson(_decodeObject(response));
        } on InvalidServerUrlException catch (e) {
          throw StorageProtocolException(
            'Server reported an unusable address: ${e.message}',
          );
        } on FormatException {
          throw const StorageProtocolException(
            'Malformed login flow credentials',
          );
        }
      case 404:
        return null; // Not approved yet.
      default:
        throw _unexpected(response, 'Login polling failed');
    }
  }

  /// Polls every [interval] until the user approves.
  ///
  /// Throws [LoginFlowCancelledException] after [timeout] (Nextcloud's poll
  /// tokens are valid for 20 minutes) or when [cancel] completes. Temporary
  /// network errors are retried.
  Future<NextcloudCredentials> waitForCredentials(
    LoginFlowSession session, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 20),
    Future<void>? cancel,
  }) async {
    var cancelled = false;
    unawaited(cancel?.then((_) => cancelled = true));
    var waited = Duration.zero;
    while (true) {
      if (cancelled) throw const LoginFlowCancelledException('Cancelled');
      try {
        final credentials = await poll(session);
        if (credentials != null) return credentials;
      } on StorageUnavailableException {
        // Flaky network while the user is in the browser; keep trying.
      }
      if (waited >= timeout) {
        throw const LoginFlowCancelledException(
          'The login was not approved in time.',
        );
      }
      await _delay(interval);
      waited += interval;
    }
  }

  void close() => _client.close();

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      final response = await request().timeout(requestTimeout);
      if (response.statusCode >= 500 ||
          response.statusCode == 408 ||
          response.statusCode == 429) {
        throw StorageUnavailableException(
          'Server unavailable (HTTP ${response.statusCode})',
        );
      }
      return response;
    } on TimeoutException {
      throw const StorageUnavailableException('Request timed out');
    } on http.ClientException catch (e) {
      throw StorageUnavailableException('Network error: ${e.message}');
    }
  }

  static Map<String, Object?> _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Fall through.
    }
    throw const StorageProtocolException('Response is not a JSON object');
  }

  static Uri _requireHttps(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const StorageProtocolException(
        'Server returned a non-HTTPS login URL',
      );
    }
    return uri;
  }

  static StorageException _unexpected(http.Response response, String message) =>
      StorageProtocolException('$message (HTTP ${response.statusCode})');
}
