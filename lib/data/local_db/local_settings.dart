import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/models/item_ids.dart';
import 'local_database.dart';

/// Per-installation settings kept in the local database.
final class LocalSettings {
  LocalSettings(this._db);

  static const _deviceIdKey = 'device_id';
  static const _deviceNameKey = 'device_name';

  final LocalDatabase _db;

  /// This installation's device ID, created on first use (SPEC.md §2).
  Future<String> deviceId({Random? random}) async {
    final existing = await _get(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = ItemIds.newDeviceId(random);
    await _set(_deviceIdKey, id);
    return id;
  }

  /// The human-readable device name, if the user set one.
  Future<String?> deviceName() => _get(_deviceNameKey);

  Future<void> setDeviceName(String name) => _set(_deviceNameKey, name.trim());

  Future<String?> _get(String key) async {
    final row = await (_db.select(
      _db.keyValues,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String? value) => _db
      .into(_db.keyValues)
      .insertOnConflictUpdate(
        KeyValuesCompanion.insert(key: key, value: Value(value)),
      );
}
