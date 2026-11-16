import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;
import 'package:xml/xml.dart';

import '../storage_backend.dart';
import 'nextcloud_credentials.dart';

const _dav = 'DAV:';

const _propfindBody =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<d:propfind xmlns:d="DAV:"><d:prop>'
    '<d:resourcetype/><d:getetag/><d:getlastmodified/><d:getcontentlength/>'
    '</d:prop></d:propfind>';

/// [StorageBackend] on Nextcloud WebDAV (SPEC.md §5, §7).
///
/// Paths are relative to `{server}/remote.php/dav/files/{loginName}/`.
/// Requires no server-side changes.
final class NextcloudWebDavBackend implements StorageBackend {
  NextcloudWebDavBackend({
    required NextcloudCredentials credentials,
    http.Client? client,
    this.userAgent = 'Specular',
    this.requestTimeout = const Duration(seconds: 30),
  }) : _credentials = credentials, // ignore: prefer_initializing_formals
       _client = client ?? http.Client();

  final NextcloudCredentials _credentials;
  final http.Client _client;
  final String userAgent;
  final Duration requestTimeout;

  @override
  Future<void> ensureDirectory(String path) async {
    final segments = _segments(path);
    if (segments.isEmpty) return;
    final response = await _send('MKCOL', _url(segments, directory: true));
    switch (response.statusCode) {
      case 201: // Created.
      case 405: // Already exists.
        return;
      case 409: // Parent missing: create it, then retry.
        if (segments.length == 1) throw _notFound('MKCOL', path, response);
        await ensureDirectory(
          segments.sublist(0, segments.length - 1).join('/'),
        );
        final retry = await _send('MKCOL', _url(segments, directory: true));
        if (retry.statusCode == 201 || retry.statusCode == 405) return;
        throw _error('MKCOL', path, retry);
      default:
        throw _error('MKCOL', path, response);
    }
  }

  @override
  Future<DirectoryListing> list(String path) async {
    final segments = _segments(path);
    final url = _url(segments, directory: true);
    final response = await _send(
      'PROPFIND',
      url,
      headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'},
      body: _propfindBody,
    );
    if (response.statusCode == 404) throw _notFound('PROPFIND', path, response);
    if (response.statusCode != 207) throw _error('PROPFIND', path, response);

    final XmlDocument document;
    try {
      document = XmlDocument.parse(response.body);
    } on XmlException catch (e) {
      throw StorageProtocolException(
        'Malformed PROPFIND response: ${e.message}',
      );
    }

    final selfSegments = _decodedSegments(url);
    String? etag;
    final entries = <RemoteEntry>[];
    for (final node in document.findAllElements(
      'response',
      namespaceUri: _dav,
    )) {
      final href = node.getElement('href', namespaceUri: _dav)?.innerText;
      final hrefUri = href == null ? null : Uri.tryParse(href.trim());
      if (hrefUri == null) continue;
      final hrefSegments = _decodedSegments(hrefUri);
      if (hrefSegments.isEmpty) continue;
      final props = _okProps(node);
      if (_sameSegments(hrefSegments, selfSegments)) {
        etag = props?.getElement('getetag', namespaceUri: _dav)?.innerText;
        continue;
      }
      final name = hrefSegments.last;
      final isDirectory =
          props
              ?.getElement('resourcetype', namespaceUri: _dav)
              ?.getElement('collection', namespaceUri: _dav) !=
          null;
      entries.add(
        RemoteEntry(
          name: name,
          isDirectory: isDirectory,
          etag: props?.getElement('getetag', namespaceUri: _dav)?.innerText,
          lastModified: _parseDate(
            props?.getElement('getlastmodified', namespaceUri: _dav)?.innerText,
          ),
          size: int.tryParse(
            props
                    ?.getElement('getcontentlength', namespaceUri: _dav)
                    ?.innerText ??
                '',
          ),
        ),
      );
    }
    return DirectoryListing(
      etag: etag,
      entries: entries,
      serverTime: _parseDate(response.headers['date']),
    );
  }

  @override
  Future<Uint8List> get(String path) async {
    final response = await _send('GET', _url(_segments(path)));
    if (response.statusCode == 200) return response.bodyBytes;
    if (response.statusCode == 404) throw _notFound('GET', path, response);
    throw _error('GET', path, response);
  }

  @override
  Future<void> put(String path, Uint8List data, {bool overwrite = true}) async {
    final response = await _send(
      'PUT',
      _url(_segments(path)),
      headers: {
        'Content-Type': 'application/octet-stream',
        if (!overwrite) 'If-None-Match': '*',
      },
      bodyBytes: data,
    );
    switch (response.statusCode) {
      case 200:
      case 201:
      case 204:
        return;
      case 412:
        throw StorageAlreadyExistsException(path);
      case 404:
      case 409:
        throw _notFound('PUT', path, response);
      default:
        throw _error('PUT', path, response);
    }
  }

  @override
  Future<void> delete(String path) async {
    final response = await _send('DELETE', _url(_segments(path)));
    switch (response.statusCode) {
      case 200:
      case 204:
        return;
      case 404:
        throw _notFound('DELETE', path, response);
      default:
        throw _error('DELETE', path, response);
    }
  }

  @override
  Future<void> move(String from, String to, {bool overwrite = false}) async {
    final response = await _send(
      'MOVE',
      _url(_segments(from)),
      headers: {
        'Destination': _url(_segments(to)).toString(),
        'Overwrite': overwrite ? 'T' : 'F',
      },
    );
    switch (response.statusCode) {
      case 201:
      case 204:
        return;
      case 412:
        throw StorageAlreadyExistsException(to);
      case 404:
      case 409:
        throw _notFound('MOVE', from, response);
      default:
        throw _error('MOVE', from, response);
    }
  }

  void close() => _client.close();

  // ---------------------------------------------------------------------------

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  Uri _url(List<String> segments, {bool directory = false}) {
    final root = _credentials.webDavRoot;
    return root.replace(
      pathSegments: [
        ...root.pathSegments.where((s) => s.isNotEmpty),
        ...segments,
        if (directory) '',
      ],
    );
  }

  /// Percent-decoded, non-empty path segments, for comparing hrefs.
  static List<String> _decodedSegments(Uri uri) =>
      uri.pathSegments.where((s) => s.isNotEmpty).toList();

  static bool _sameSegments(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The `<d:prop>` of the propstat with a 200 status.
  static XmlElement? _okProps(XmlElement response) {
    for (final propstat in response.findElements(
      'propstat',
      namespaceUri: _dav,
    )) {
      final status = propstat
          .getElement('status', namespaceUri: _dav)
          ?.innerText;
      if (status != null && status.contains(' 200 ')) {
        return propstat.getElement('prop', namespaceUri: _dav);
      }
    }
    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return parseHttpDate(value).toUtc();
    } on FormatException {
      return null;
    }
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
    Uint8List? bodyBytes,
  }) async {
    final request = http.Request(method, url)
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': _credentials.authorizationHeader,
        'User-Agent': userAgent,
        ...headers,
      });
    if (body != null) request.body = body;
    if (bodyBytes != null) request.bodyBytes = bodyBytes;

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(requestTimeout);
      response = await http.Response.fromStream(streamed)
          .timeout(requestTimeout);
    } on TimeoutException {
      throw StorageUnavailableException('$method timed out');
    } on http.ClientException catch (e) {
      throw StorageUnavailableException('$method failed: ${e.message}');
    }

    final status = response.statusCode;
    if (status == 401) {
      throw const StorageUnauthorizedException(
        'Nextcloud rejected the app password. Please log in again.',
      );
    }
    if (status >= 500 || status == 408 || status == 429) {
      throw StorageUnavailableException('Server unavailable (HTTP $status)');
    }
    return response;
  }

  /// Error messages contain the method, the relative path and the status
  /// only: never URLs with user names or any credentials.
  static StorageException _notFound(
    String method,
    String path,
    http.Response response,
  ) => StorageNotFoundException(
    '$method $path: not found (HTTP ${response.statusCode})',
  );

  static StorageException _error(
    String method,
    String path,
    http.Response response,
  ) => StorageProtocolException(
    '$method $path: unexpected HTTP ${response.statusCode}',
  );
}
