import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:specular/core/updates/releases.dart';
import 'package:specular/platform/updater/update_service.dart';
import 'package:specular/ui/update/update_banner.dart';
import 'package:specular/ui/update/update_controller.dart';

import '../platform/update_service_test.dart' show fakeGitHub;

class _Settings implements UpdateSettings {
  bool enabled = true;

  @override
  Future<bool> autoCheckUpdates() async => enabled;

  @override
  Future<void> setAutoCheckUpdates(bool value) async => enabled = value;
}

void main() {
  const channel = MethodChannel('de.rixk.specular/updates');
  late List<String> installed;
  late String installAnswer;
  late Directory temp;

  setUp(() async {
    installed = [];
    installAnswer = 'started';
    temp = Directory.systemTemp.createTempSync('upd-ui');
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          installed.add((call.arguments as Map)['path'] as String);
          return installAnswer;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    temp.deleteSync(recursive: true);
  });

  UpdateController controller({
    UpdatePlatform platform = UpdatePlatform.android,
    _Settings? settings,
  }) => UpdateController(
    service: UpdateService(
      currentVersion: Version(0, 1, 0),
      platform: platform,
      client: fakeGitHub(),
      downloadDirectory: () async => temp,
    ),
    settings: settings ?? _Settings(),
    quitApp: () {},
  );

  Future<void> pumpBanner(WidgetTester tester, UpdateController c) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateBanner(controller: c, openUrl: (_) async => true),
          ),
        ),
      );

  testWidgets('checks at start and shows the banner', (tester) async {
    final c = controller();
    await tester.runAsync(c.start);
    await pumpBanner(tester, c);

    expect(find.text('Update available · v0.2.0'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
    c.dispose();
  });

  testWidgets('does not check by itself when switched off', (tester) async {
    final c = controller(settings: _Settings()..enabled = false);
    await tester.runAsync(c.start);
    await pumpBanner(tester, c);

    expect(find.byKey(const Key('update-banner')), findsNothing);
    expect(c.autoCheck.value, isFalse);
    c.dispose();
  });

  testWidgets('dismissing hides it for this version', (tester) async {
    final c = controller();
    await tester.runAsync(c.start);
    await pumpBanner(tester, c);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-banner')), findsNothing);

    await tester.runAsync(c.check);
    await tester.pump();
    expect(find.byKey(const Key('update-banner')), findsNothing);
    c.dispose();
  });

  testWidgets('Install downloads, verifies and hands the APK to Android', (
    tester,
  ) async {
    final c = controller();
    await tester.runAsync(c.start);
    await pumpBanner(tester, c);

    await tester.runAsync(c.install);
    await tester.pump();

    expect(installed.single, endsWith('specular-0.2.0-android.apk'));
    expect(find.text('Installing…'), findsOneWidget);
    c.dispose();
  });

  testWidgets('asks to allow installing apps first', (tester) async {
    installAnswer = 'permission';
    final c = controller();
    await tester.runAsync(c.start);
    await pumpBanner(tester, c);

    await tester.runAsync(c.install);
    await tester.pump();

    expect(
      find.textContaining('Allow Specular to install apps'),
      findsOneWidget,
    );
    expect(find.text('Install'), findsOneWidget);
    c.dispose();
  });

  testWidgets('Linux only points to the release page', (tester) async {
    final c = controller(platform: UpdatePlatform.linux);
    await tester.runAsync(c.start);
    await pumpBanner(tester, c);

    expect(find.text('Install'), findsNothing);
    expect(find.text('Open release page'), findsOneWidget);
    expect(find.textContaining('package manager'), findsOneWidget);
    c.dispose();
  });
}
