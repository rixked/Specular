import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../backends/nextcloud/login_flow.dart';
import '../../backends/nextcloud/nextcloud_credentials.dart';
import '../../backends/storage_backend.dart';
import '../common/url_opener.dart';

/// First launch (SPEC.md §3.1): the user enters their Nextcloud address,
/// approves access in the browser, and never types a password.
///
/// Deliberately plain until the visual direction is chosen (SPEC.md §9).
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
  final NextcloudLoginFlow Function() flowFactory;
  final UrlOpener openUrl;

  /// Shown above the form, for example after the app password was revoked.
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { form, starting, waiting, finishing }

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  _Step _step = _Step.form;
  String? _error;
  LoginFlowSession? _session;
  bool _browserFailed = false;
  Completer<void>? _cancel;
  NextcloudLoginFlow? _flow;

  @override
  void dispose() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _flow?.close();
    _server.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    final flow = widget.flowFactory();
    final cancel = Completer<void>();
    setState(() {
      _flow = flow;
      _cancel = cancel;
      _step = _Step.starting;
      _error = null;
      _browserFailed = false;
    });

    try {
      final session = await flow.start(_server.text);
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
      await widget.onLoggedIn(credentials);
    } on InvalidServerUrlException catch (e) {
      _fail(e.message);
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
      body: Center(
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
    );
  }

  Widget _buildForm(BuildContext context) {
    final busy = _step == _Step.starting;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Specular', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Connect your Nextcloud. You approve access in the browser, '
          'no password needed.',
          style: theme.textTheme.bodyMedium,
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
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
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
