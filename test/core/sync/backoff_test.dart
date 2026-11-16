import 'package:flutter_test/flutter_test.dart';
import 'package:specular/core/sync/backoff.dart';

void main() {
  test('doubles up to the cap', () {
    const backoff = Backoff();
    expect(backoff.delayAfter(1), const Duration(seconds: 5));
    expect(backoff.delayAfter(2), const Duration(seconds: 10));
    expect(backoff.delayAfter(4), const Duration(seconds: 40));
    expect(backoff.delayAfter(6), const Duration(minutes: 2));
    expect(backoff.delayAfter(1000), const Duration(minutes: 2));
  });
}
