import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/notifiers/polling_notifier.dart';

void main() {
  group('PollingNotifier', () {
    test('emits every interval while running', () {
      fakeAsync((async) {
        final notifier = PollingNotifier();
        var ticks = 0;
        notifier.changes.listen((_) => ticks++);

        notifier.start();
        async.elapse(const Duration(seconds: 46));
        expect(ticks, 3);

        notifier.stop();
        async.elapse(const Duration(minutes: 1));
        expect(ticks, 3);
        notifier.dispose();
      });
    });

    test('nudge emits immediately and restarts the interval', () {
      fakeAsync((async) {
        final notifier = PollingNotifier()..start();
        var ticks = 0;
        notifier.changes.listen((_) => ticks++);

        async.elapse(const Duration(seconds: 10));
        notifier.nudge();
        async.flushMicrotasks();
        expect(ticks, 1);

        async.elapse(const Duration(seconds: 14));
        expect(ticks, 1, reason: 'no tick 5 s after the nudge');
        async.elapse(const Duration(seconds: 1));
        expect(ticks, 2);
        notifier.dispose();
      });
    });

    test('start is idempotent', () {
      fakeAsync((async) {
        final notifier = PollingNotifier();
        var ticks = 0;
        notifier.changes.listen((_) => ticks++);
        notifier
          ..start()
          ..start();
        async.elapse(const Duration(seconds: 15));
        expect(ticks, 1);
        notifier.dispose();
      });
    });
  });
}
