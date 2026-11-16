import '../models/item.dart';
import '../models/json_utils.dart';

/// Information a handler needs to build a note, beyond the item itself.
final class NoteContext {
  const NoteContext({required this.deviceName});

  /// The human-readable name of the device that sent the item.
  final String deviceName;
}

/// A note ready to be written to `/Notes/` (SPEC.md §5.3).
final class NoteDraft {
  const NoteDraft({required this.title, required this.body});

  /// Unsanitized title. Use [noteFileName] to turn it into a file name.
  final String title;
  final String body;
}

/// Maximum title length for text items, in characters (SPEC.md §5.3).
const textTitleMaxLength = 60;

/// Upper bound for any title, to keep file names manageable.
const titleHardMaxLength = 120;

const _fallbackTitle = 'Note';

/// Characters that are invalid in file names on Windows, Linux, Android or
/// Nextcloud, plus control characters.
final _invalidFileNameChars = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');
final _whitespaceRun = RegExp(r'\s+');

/// Windows device names that cannot be used as a base file name.
const _reservedWindowsNames = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// The footer line appended to every note body.
String noteFooter(Item item, NoteContext context) =>
    'Sent from ${context.deviceName} · ${formatDate(item.createdAt.toLocal())}';

/// Truncates [text] to at most [maxLength] characters without splitting a
/// surrogate pair.
String truncateRunes(String text, int maxLength) {
  final runes = text.runes;
  if (runes.length <= maxLength) return text;
  return String.fromCharCodes(runes.take(maxLength)).trimRight();
}

/// Turns [title] into a safe base file name (without extension): strips
/// invalid characters, collapses whitespace, and avoids empty or reserved
/// names.
String sanitizeNoteTitle(String title) {
  var result = title
      .replaceAll(_whitespaceRun, ' ')
      .replaceAll(_invalidFileNameChars, '')
      .trim();
  result = truncateRunes(result, titleHardMaxLength);
  // Windows does not allow trailing dots or spaces.
  result = result.replaceFirst(RegExp(r'[. ]+$'), '');
  // Leading dots would create hidden files.
  result = result.replaceFirst(RegExp(r'^\.+'), '').trim();
  if (result.isEmpty) return _fallbackTitle;
  if (_reservedWindowsNames.contains(result.toUpperCase())) {
    return '$_fallbackTitle $result';
  }
  return result;
}

/// Picks `<title>.md`, or `<title> (2).md`, `<title> (3).md`, … if the name
/// is already taken. Comparison is case-insensitive, because some clients
/// that sync the Notes folder have case-insensitive file systems.
String noteFileName(String title, Iterable<String> existingFileNames) {
  final base = sanitizeNoteTitle(title);
  final taken = {for (final name in existingFileNames) name.toLowerCase()};
  var candidate = '$base.md';
  for (var n = 2; taken.contains(candidate.toLowerCase()); n++) {
    candidate = '$base ($n).md';
  }
  return candidate;
}
