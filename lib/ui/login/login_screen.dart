import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../backends/nextcloud/login_flow.dart';
import '../../backends/nextcloud/nextcloud_credentials.dart';
import '../../backends/storage_backend.dart';
import '../common/specular_background.dart';
import '../common/url_opener.dart';
import '../theme/tokens.dart';

/// Creates a login flow for [server]. [pinnedCertificate] is a self-signed
/// certificate's fingerprint the user explicitly trusted, or null.
typedef LoginFlowFactory = NextcloudLoginFlow Function(
  Uri server,
  String? pinnedCertificate,
);

/// First launch (SPEC.md §3.1): the user enters their Nextcloud address,
/// approves access in the browser, and never types a password.
///
/// A self-signed certificate is never accepted silently (SPEC.md §8): the
/// screen shows its fingerprint and continues only after the user trusts it.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLoggedIn,
    required this.flowFactory,
    this.openUrl = openInBrowser,
    this.message,
  });

  /// Called with the new credentials once the user approved.
  final Future<void> Function(NextcloudCredentials credentials) onLoggedIn;

  /// Creates the login flow; one per attempt.
  final LoginFlowFactory flowFactory;
  final UrlOpener openUrl;

  /// Shown above the form, for example after the app password was revoked.
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { form, starting, waiting, finishing }

/// Asks the user to trust a self-signed certificate after comparing its
/// fingerprint (SPEC.md §8).
class _TrustCertificatePanel extends StatelessWidget {
  const _TrustCertificatePanel({
    required this.certificate,
    required this.onTrust,
    required this.onCancel,
  });

  final StorageUntrustedCertificateException certificate;
  final VoidCallback onTrust;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(SpecularRadii.card),
        border: Border.all(color: SpecularColors.pendingText),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: SpecularColors.pendingText,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Untrusted certificate',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Your system doesn't trust the certificate of ${certificate.host}. "
            'Only continue if you set up this server yourself and this '
            "fingerprint matches the server's certificate:",
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 10),
          SelectableText(
            'SHA-256  ${certificate.fingerprint}',
            key: const Key('fingerprint'),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: SpecularColors.icon,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
              FilledButton(
                key: const Key('trust'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: onTrust,
                child: const Text('Trust and continue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  _Step _step = _Step.form;
  String? _error;
  LoginFlowSession? _session;
  bool _browserFailed = false;
  Completer<void>? _cancel;
  NextcloudLoginFlow? _flow;

  /// A certificate waiting for the user's decision.
  StorageUntrustedCertificateException? _untrusted;

  /// The fingerprint the user trusted, and the host it was trusted for.
  String? _pinned;
  String? _pinnedHost;

  @override
  void dispose() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _flow?.close();
    _server.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    final Uri server;
    try {
      server = normalizeServerUrl(_server.text);
    } on InvalidServerUrlException catch (e) {
      _fail(e.message);
      return;
    }
    // A trust decision only ever applies to the host it was made for.
    final pinned = _pinnedHost == server.host ? _pinned : null;
    final flow = widget.flowFactory(server, pinned);
    final cancel = Completer<void>();
    setState(() {
      _flow = flow;
      _cancel = cancel;
      _step = _Step.starting;
      _error = null;
      _untrusted = null;
      _browserFailed = false;
    });

    try {
      final session = await flow.start(server.toString());
      if (cancel.isCompleted) return;
      final opened = await widget.openUrl(session.loginUrl);
      if (!mounted || cancel.isCompleted) return;
      setState(() {
        _session = session;
        _browserFailed = !opened;
        _step = _Step.waiting;
      });

      final credentials = await flow.waitForCredentials(
        session,
        cancel: cancel.future,
      );
      if (!mounted) return;
      setState(() => _step = _Step.finishing);
      await widget.onLoggedIn(credentials.withPinnedCertificate(pinned));
    } on InvalidServerUrlException catch (e) {
      _fail(e.message);
    } on StorageUntrustedCertificateException catch (e) {
      _fail(null);
      if (mounted) setState(() => _untrusted = e);
    } on LoginFlowCancelledException catch (e) {
      _fail(cancel.isCompleted ? null : e.message);
    } on StorageUnavailableException {
      _fail(
        "Couldn't reach the server. Check the address and your connection.",
      );
    } on StorageException {
      _fail("This doesn't look like a Nextcloud server.");
    } on Object {
      // For example secure storage being unavailable while saving.
      _fail('Login failed. Please try again.');
    } finally {
      flow.close();
      if (identical(_flow, flow)) _flow = null;
    }
  }

  void _trustCertificate() {
    final untrusted = _untrusted;
    if (untrusted == null) return;
    setState(() {
      _pinned = untrusted.fingerprint;
      _pinnedHost = untrusted.host;
      _untrusted = null;
    });
    unawaited(_logIn());
  }

  void _cancelLogin() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _fail(null);
  }

  void _fail(String? message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.form;
      _error = message;
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpecularColors.background,
      body: SpecularBackground(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: switch (_step) {
                  _Step.form || _Step.starting => _buildForm(context),
                  _Step.waiting => _buildWaiting(context),
                  _Step.finishing => const Center(
                    child: CircularProgressIndicator(),
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final busy = _step == _Step.starting;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Specular',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Connect your Nextcloud. You approve access in the browser, '
          'no password needed.',
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: SpecularColors.textSecondary,
          ),
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.message!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          key: const Key('server'),
          controller: _server,
          enabled: !busy,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => busy ? null : _logIn(),
          decoration: InputDecoration(
            labelText: 'Nextcloud address',
            hintText: 'cloud.example.com',
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        if (_untrusted case final untrusted?)
          _TrustCertificatePanel(
            certificate: untrusted,
            onTrust: _trustCertificate,
            onCancel: () => setState(() => _untrusted = null),
          )
        else
          FilledButton(
            key: const Key('login'),
            onPressed: busy ? null : _logIn,
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Log in'),
          ),
      ],
    );
  }

  Widget _buildWaiting(BuildContext context) {
    final session = _session!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Approve in your browser', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          _browserFailed
              ? "Couldn't open the browser. Open this link to approve access:"
              : 'Log in to Nextcloud and grant access. This screen continues '
                    'automatically.',
        ),
        if (_browserFailed) ...[
          const SizedBox(height: 8),
          SelectableText(session.loginUrl.toString()),
        ],
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: session.loginUrl.toString()),
              ),
              child: const Text('Copy link'),
            ),
            TextButton(
              onPressed: () => widget.openUrl(session.loginUrl),
              child: const Text('Open again'),
            ),
            TextButton(
              key: const Key('cancel'),
              onPressed: _cancelLogin,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
