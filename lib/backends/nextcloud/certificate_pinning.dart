import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../storage_backend.dart';

/// SHA-256 of a DER-encoded certificate as `AB:CD:EF:…`.
String certificateFingerprint(List<int> der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// Whether a certificate the system rejected may be used anyway: only when
/// the user pinned exactly this certificate for exactly this host.
bool isPinnedCertificate({
  required String fingerprint,
  required String host,
  required String expectedHost,
  required String? pinnedFingerprint,
}) =>
    pinnedFingerprint != null &&
    host.toLowerCase() == expectedHost.toLowerCase() &&
    fingerprint == pinnedFingerprint;

/// HTTP client for one Nextcloud server (SPEC.md §8).
///
/// Certificates the system trusts work as usual. A self-signed certificate
/// is accepted only if its fingerprint was pinned for this host; otherwise
/// the request fails with [StorageUntrustedCertificateException] carrying
/// the fingerprint, so the user can compare and trust it explicitly. Never
/// accepted silently.
final class PinningHttpClient extends http.BaseClient {
  PinningHttpClient({required this.host, this.pinnedFingerprint}) {
    final io = HttpClient()
      ..badCertificateCallback = (cert, certHost, port) {
        final fingerprint = certificateFingerprint(cert.der);
        if (isPinnedCertificate(
          fingerprint: fingerprint,
          host: certHost,
          expectedHost: host,
          pinnedFingerprint: pinnedFingerprint,
        )) {
          return true;
        }
        _rejected = fingerprint;
        return false;
      };
    _inner = IOClient(io);
  }

  /// The server's host name.
  final String host;
  final String? pinnedFingerprint;

  late final http.Client _inner;
  String? _rejected;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _rejected = null;
    try {
      return await _inner.send(request);
    } on Object catch (error) {
      final rejected = _rejected;
      if (rejected != null) {
        throw StorageUntrustedCertificateException(host, rejected);
      }
      if (error is HandshakeException) {
        throw http.ClientException('TLS handshake failed', request.url);
      }
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
