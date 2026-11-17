import 'package:flutter_test/flutter_test.dart';
import 'package:specular/ui/common/glass_card.dart';
import 'package:specular/ui/common/relative_time.dart';

void main() {
  test('relativeAge', () {
    expect(relativeAge(const Duration(seconds: 20)), 'just now');
    expect(relativeAge(const Duration(minutes: 2)), '2 min');
    expect(relativeAge(const Duration(hours: 3, minutes: 59)), '3 h');
    expect(relativeAge(const Duration(days: 1, hours: 2)), '1 day');
    expect(relativeAge(const Duration(days: 3)), '3 days');
  });

  test('expiryHint only near the end of the 7 days', () {
    expect(expiryHint(const Duration(days: 3)), isNull);
    expect(expiryHint(const Duration(days: 5, hours: 1)), 'expires tomorrow');
    expect(expiryHint(const Duration(days: 6, hours: 2)), 'expires today');
  });

  test('keptAgo', () {
    expect(keptAgo(const Duration(seconds: 5)), 'kept just now');
    expect(keptAgo(const Duration(hours: 3)), 'kept 3 h ago');
    expect(keptAgo(const Duration(days: 1)), 'kept yesterday');
    expect(keptAgo(const Duration(days: 4)), 'kept 4 days ago');
    expect(keptAgo(const Duration(days: 9)), 'kept last week');
    expect(keptAgo(const Duration(days: 21)), 'kept 3 weeks ago');
  });

  test('sheen fades from 1 to 0 over 7 days', () {
    expect(sheenForAge(Duration.zero), 1);
    expect(
      sheenForAge(const Duration(days: 3, hours: 12)),
      closeTo(0.5, 0.001),
    );
    expect(sheenForAge(const Duration(days: 7)), 0);
    expect(sheenForAge(const Duration(days: 30)), 0);
  });
}
