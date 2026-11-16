import 'dart:convert';

import 'json_utils.dart';

/// An installation of Specular (SPEC.md §2).
///
/// Stored as `/Specular/devices/<id>.json`. Only the device itself writes
/// its own file.
final class Device {
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeen,
  });

  factory Device.fromJson(Map<String, Object?> json) => Device(
    id: requireField<String>(json, 'id'),
    name: requireField<String>(json, 'name'),
    platform: requireField<String>(json, 'platform'),
    lastSeen: requireUtcDate(json, 'lastSeen'),
  );

  factory Device.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Device file is not a JSON object', source);
    }
    return Device.fromJson(decoded);
  }

  final String id;

  /// Human-readable name, for example "Arch PC" or "Pixel".
  final String name;

  /// `linux`, `windows` or `android`.
  final String platform;
  final DateTime lastSeen;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'lastSeen': formatUtcSeconds(lastSeen),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
