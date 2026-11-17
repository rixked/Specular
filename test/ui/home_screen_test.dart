import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:specular/app/sync_coordinator.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/remote_layout.dart';
import 'package:specular/core/sync/sync_engine.dart';
import 'package:specular/notifiers/manual_notifier.dart';
import 'package:specular/ui/home/home_screen.dart';
import 'package:specular/ui/theme/specular_theme.dart';

import '../fakes/fake_storage_backend.dart';

const _longText =
    'Pick up the film at 5, roll 36, and ask whether they can scan the '
    'medium format negatives too';

/// Everything a HomeScreen test needs. Created inside each test, so the
/// engine's futures run in the test's fake time.
class _Harness {
  _Harness() {
    engine = SyncEngine(
      backend: backend,
      store: InMemoryLocalStore(),
      deviceId: 'a1b2c3',
      clock: () => DateTime.utc(2026, 11, 16, 12),
    );
    coordinator = SyncCoordinator(engine: engine, trigger: ManualNotifier());
  }

  final backend = FakeStorageBackend();
  late final SyncEngine engine;
  late final SyncCoordinator coordinator;
  final opened = <Uri>[];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: specularTheme(),
        home: HomeScreen(
          engine: engine,
          coordinator: coordinator,
          onLogOut: () {},
          clock: () => DateTime.utc(2026, 11, 16, 12, 5),
          openUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  late List<String> clipboard;

  setUp(() {
    clipboard = [];
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': 'https://example.com/pasted'};
          }
          return null;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Unmounts the screen so its timers are cancelled.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('long text is cut to one line and can be expanded and '
      'collapsed again', (tester) async {
    final h = _Harness();
    final id = (await h.engine.send(_longText)).id;
    await h.pump(tester);

    final title = find.textContaining('Pick up the film');
    expect(tester.widget<Text>(title).maxLines, 1);
    expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);

    await tester.tap(find.byKey(ValueKey('expand-$id')));
    await tester.pumpAndSettle();
    expect(find.text(_longText), findsOneWidget);
    expect(tester.widget<Text>(find.text(_longText)).maxLines, isNull);
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('expand-$id')));
    await tester.pumpAndSettle();
    expect(find.text('Keep'), findsNothing);
    await unmount(tester);
  });

  testWidgets('every item can be copied', (tester) async {
    final h = _Harness();
    final id = (await h.engine.send('https://example.com/a')).id;
    await h.pump(tester);

    await tester.tap(find.byKey(ValueKey('copy-$id')));
    await tester.pump();

    expect(clipboard, ['https://example.com/a']);
    expect(find.text('Copied'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('tapping a link opens it in the browser', (tester) async {
    final h = _Harness();
    await h.engine.send('https://example.com/video');
    await h.pump(tester);

    await tester.tap(find.text('https://example.com/video'));
    await tester.pump();

    expect(h.opened.single.toString(), 'https://example.com/video');
    await unmount(tester);
  });

  testWidgets('sending shows "Sent" briefly, then hides it', (tester) async {
    final h = _Harness();
    await h.pump(tester);

    await tester.enterText(find.byKey(const Key('send')), 'hello there');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('hello there'), findsOneWidget);
    final toast = find.ancestor(
      of: find.text('Sent'),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(toast).opacity, 1);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(tester.widget<AnimatedOpacity>(toast).opacity, 0);
    await unmount(tester);
  });

  testWidgets('Ctrl+V anywhere in the window sends the clipboard', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(find.text('https://example.com/pasted'), findsOneWidget);
    expect(
      (await h.engine.store.items()).single.item.content,
      'https://example.com/pasted',
    );
    await unmount(tester);
  });

  testWidgets('Ctrl+V in the send field pastes instead of sending', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);

    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(await h.engine.store.items(), isEmpty);
    await unmount(tester);
  });

  Future<void> pressCtrlV(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Ctrl+V keeps working after typing and sending in the field', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);

    await pressCtrlV(tester);
    expect(await h.engine.store.items(), hasLength(1));

    await tester.tap(find.byKey(const Key('send')));
    await tester.enterText(find.byKey(const Key('send')), 'typed by hand');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    await tester.pump();
    expect(await h.engine.store.items(), hasLength(2));

    await pressCtrlV(tester);
    await pressCtrlV(tester);
    expect(await h.engine.store.items(), hasLength(4));
    await unmount(tester);
  });

  testWidgets('Esc leaves the field, then Ctrl+V sends', (tester) async {
    final h = _Harness();
    await h.pump(tester);

    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await pressCtrlV(tester);

    expect(await h.engine.store.items(), hasLength(1));
    await unmount(tester);
  });

  testWidgets('Ctrl+V works wherever the focus ended up', (tester) async {
    final h = _Harness();
    await h.pump(tester);

    // For example after clicking around: focus outside this screen.
    FocusManager.instance.rootScope.requestFocus();
    await tester.pump();
    await pressCtrlV(tester);

    expect(await h.engine.store.items(), hasLength(1));
    await unmount(tester);
  });

  testWidgets('kept items leave the inbox and show up under Kept', (
    tester,
  ) async {
    final h = _Harness();
    final id = (await h.engine.send('Groceries\nmilk, eggs')).id;
    await h.pump(tester);

    await tester.tap(find.byKey(ValueKey('expand-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(find.textContaining('milk, eggs'), findsNothing);
    expect(h.backend.filesIn(RemoteLayout.notes), ['Groceries.md']);

    await tester.tap(find.byKey(const Key('tab-kept')));
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(
      find.text('Saved permanently in Nextcloud · Notes › Specular'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('expand-kept-Groceries.md')));
    await tester.pumpAndSettle();
    expect(find.textContaining('milk, eggs'), findsOneWidget);
    await unmount(tester);
  });
}
