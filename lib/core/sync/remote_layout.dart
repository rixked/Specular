/// Paths of Specular's data in the user's storage (SPEC.md §5).
abstract final class RemoteLayout {
  static const root = 'Specular';
  static const inbox = 'Specular/inbox';
  static const devices = 'Specular/devices';

  /// Attachments (v0.2+).
  static const files = 'Specular/files';

  /// Kept notes. Matches the Nextcloud Notes app's default folder.
  static const notes = 'Notes';

  /// Directories that must exist for v0.1.
  static const requiredDirectories = [root, inbox, devices, notes];

  static const itemSuffix = '.json';

  static String itemPath(String itemId) => '$inbox/$itemId$itemSuffix';
  static String devicePath(String deviceId) => '$devices/$deviceId.json';
  static String notePath(String fileName) => '$notes/$fileName';
}
