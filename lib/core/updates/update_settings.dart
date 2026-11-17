/// Where the update check's settings live (implemented by `LocalSettings`).
abstract interface class UpdateSettings {
  /// Whether the app checks by itself (SPEC.md §3.6: on by default).
  Future<bool> autoCheckUpdates();
  Future<void> setAutoCheckUpdates(bool enabled);
}
