import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:specular/backends/nextcloud/login_flow.dart';
import 'package:specular/backends/nextcloud/nextcloud_credentials.dart';
import 'package:specular/ui/login/login_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// A fake Nextcloud that approves the login after [pendingPolls] polls.
MockClient _nextcloud({int pendingPolls = 1, List<Uri>? requests}) {
  var polls = 0;
  return MockClient((request) async {
    requests?.add(request.url);
    if (request.url.path.endsWith('/index.php/login/v2')) {
      return _json({
        'poll': {
          'token': 'tok',
          'endpoint': 'https://cloud.example.com/login/v2/poll',
        },
        'login': 'https://cloud.example.com/login/v2/flow/abc',
      });
    }
    if (polls++ < pendingPolls) return http.Response('', 404);
    return _json({
      'server': 'https://cloud.example.com',
      'loginName': 'alice',
      'appPassword': 'app-password',
    });
  });
}

class _Harness {
  final opened = <Uri>[];
  final loggedIn = <NextcloudCredentials>[];
  bool browserWorks = true;

  Widget build(http.Client client) => MaterialApp(
    home: LoginScreen(
      flowFactory: () => NextcloudLoginFlow(
        client: client,
        delay: (_) => Future<void>.delayed(const Duration(milliseconds: 100)),
      ),
      openUrl: (url) async {
        opened.add(url);
        return browserWorks;
      },
      onLoggedIn: (c) async => loggedIn.add(c),
    ),
  );
}

/// Advances fake time without waiting for spinners to settle.
Future<void> _advance(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('logs in through the browser without a password', (tester) async {
    final harness = _Harness();
    final requests = <Uri>[];
    await tester.pumpWidget(
      harness.build(_nextcloud(pendingPolls: 2, requests: requests)),
    );

    await tester.enterText(
      find.byKey(const Key('server')),
      'cloud.example.com',
    );
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Approve in your browser'), findsOneWidget);
    expect(
      harness.opened.single.toString(),
      'https://cloud.example.com/login/v2/flow/abc',
    );
    expect(
      requests.first.toString(),
      'https://cloud.example.com/index.php/login/v2',
    );

    await _advance(tester);

    expect(harness.loggedIn.single.loginName, 'alice');
    expect(harness.loggedIn.single.appPassword, 'app-password');
    expect(find.text('app-password'), findsNothing);
  });

  testWidgets('rejects http:// before contacting anything', (tester) async {
    final harness = _Harness();
    final requests = <Uri>[];
    await tester.pumpWidget(harness.build(_nextcloud(requests: requests)));

    await tester.enterText(
      find.byKey(const Key('server')),
      'http://cloud.example.com',
    );
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();

    expect(find.textContaining('only connects over HTTPS'), findsOneWidget);
    expect(requests, isEmpty);
    expect(harness.opened, isEmpty);
  });

  testWidgets('explains when the server is unreachable', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(
      harness.build(
        MockClient((_) async => throw http.ClientException('No route')),
      ),
    );

    await tester.enterText(find.byKey(const Key('server')), 'nope.example');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
  });

  testWidgets('explains when it is not a Nextcloud server', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(
      harness.build(MockClient((_) async => http.Response('<html>', 404))),
    );

    await tester.enterText(find.byKey(const Key('server')), 'example.com');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining("doesn't look like a Nextcloud"),
      findsOneWidget,
    );
  });

  testWidgets('can be cancelled while waiting for approval', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build(_nextcloud(pendingPolls: 1000)));

    await tester.enterText(
      find.byKey(const Key('server')),
      'cloud.example.com',
    );
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Approve in your browser'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel')));
    await _advance(tester, 3);

    expect(find.byKey(const Key('login')), findsOneWidget);
    expect(harness.loggedIn, isEmpty);
  });

  testWidgets('shows the link when the browser cannot be opened', (
    tester,
  ) async {
    final harness = _Harness()..browserWorks = false;
    await tester.pumpWidget(harness.build(_nextcloud(pendingPolls: 1000)));

    await tester.enterText(
      find.byKey(const Key('server')),
      'cloud.example.com',
    );
    await tester.tap(find.byKey(const Key('login')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("Couldn't open the browser"), findsOneWidget);
    expect(
      find.text('https://cloud.example.com/login/v2/flow/abc'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('cancel')));
    await _advance(tester, 3);
  });

  testWidgets('shows a message passed in, e.g. after a revoked password', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          message: 'Please log in again.',
          flowFactory: NextcloudLoginFlow.new,
          onLoggedIn: (_) async {},
        ),
      ),
    );
    expect(find.text('Please log in again.'), findsOneWidget);
  });
}
