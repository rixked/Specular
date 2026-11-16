import 'dart:math';

import 'json_utils.dart';

/// Generation and validation of item and device IDs (SPEC.md §5.2).
abstract final class ItemIds {
  static final _idPattern = RegExp(r'^\d{8}T\d{6}Z-[0-9a-z]+-[0-9a-z]+$');

  /// Returns `<UTC timestamp>-<deviceId>-<random>`, for example
  /// `20261116T103512Z-a1b2c3-7f9e2d`. Sortable by time and unique without
  /// coordination between devices.
  static String generate({
    required DateTime now,
    required String deviceId,
    Random? random,
  }) =>
      '${formatCompactUtc(now)}-$deviceId-${_hex(random ?? Random.secure(), 6)}';

  /// A new random device ID, for example `a1b2c3`.
  static String newDeviceId([Random? random]) =>
      _hex(random ?? Random.secure(), 6);

  /// Whether [id] has the item ID format. Also guarantees that the ID is
  /// safe to use as a file name.
  static bool isValid(String id) => _idPattern.hasMatch(id);

  static String _hex(Random random, int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
