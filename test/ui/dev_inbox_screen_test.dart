import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:specular/app/sync_coordinator.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/sync_engine.dart';
import 'package:specular/notifiers/manual_notifier.dart';
import 'package:specular/ui/inbox/dev_inbox_screen.dart';

import '../fakes/fake_storage_backend.dart';

void main() {
  late SyncEngine engine;
  late SyncCoordinator coordinator;
  late List<String> clipboard;
  late List<Uri> opened;

  Future<void> pumpInbox(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DevInboxScreen(
          engine: engine,
          coordinator: coordinator,
          onLogOut: () {},
          openUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    clipboard = [];
    opened = [];
    engine = SyncEngine(
      backend: FakeStorageBackend(),
      store: InMemoryLocalStore(),
      deviceId: 'a1b2c3',
    );
    coordinator = SyncCoordinator(engine: engine, trigger: ManualNotifier());
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('every item can be copied', (tester) async {
    late String id;
    await tester.runAsync(() async {
      id = (await engine.send('https://example.com/a')).id;
    });
    await pumpInbox(tester);

    await tester.tap(find.byKey(Key('copy-$id')));
    await tester.pump();

    expect(clipboard, ['https://example.com/a']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('tapping a link opens it in the browser', (tester) async {
    await tester.runAsync(() => engine.send('https://example.com/video'));
    await pumpInbox(tester);

    await tester.tap(find.text('https://example.com/video'));
    await tester.pump();

    expect(opened.single.toString(), 'https://example.com/video');
  });

  testWidgets('tapping text shows it in full, selectable and copyable', (
    tester,
  ) async {
    await tester.runAsync(() => engine.send('Shopping list\nmilk\neggs'));
    await pumpInbox(tester);

    await tester.tap(find.textContaining('Shopping list'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.byKey(const Key('detail-copy')));
    await tester.pump();
    expect(clipboard, ['Shopping list\nmilk\neggs']);
  });
}
