/// Paths of Specular's data in the user's storage (SPEC.md §5).
abstract final class RemoteLayout {
  static const root = 'Specular';
  static const inbox = 'Specular/inbox';
  static const devices = 'Specular/devices';

  /// Attachments (v0.2+).
  static const files = 'Specular/files';

  /// The Nextcloud Notes app's default folder.
  static const notesRoot = 'Notes';

  /// Kept notes (SPEC.md §3.4.1). A subfolder of the Notes app's folder, so
  /// the app shows them as their own category "Specular", apart from the
  /// user's other notes.
  static const notes = '$notesRoot/Specular';

  static const noteSuffix = '.md';

  /// Directories that must exist for v0.1.
  static const requiredDirectories = [root, inbox, devices, notesRoot, notes];

  static const itemSuffix = '.json';

  static String itemPath(String itemId) => '$inbox/$itemId$itemSuffix';
  static String devicePath(String deviceId) => '$devices/$deviceId.json';
  static String notePath(String fileName) => '$notes/$fileName';
}
