import '../models/item.dart';
import '../models/item_type.dart';
import 'item_type_handler.dart';
import 'note_draft.dart';

/// Handles `text` items. Accepts any non-empty input, so it must be
/// registered after more specific handlers.
final class TextHandler extends ItemTypeHandler {
  const TextHandler();

  /// The first non-empty line of [text], truncated to ~60 characters.
  static String firstLine(String text) {
    final line = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return truncateRunes(line, textTitleMaxLength);
  }

  @override
  ItemType get type => ItemType.text;

  @override
  bool detects(String input) => input.trim().isNotEmpty;

  @override
  ItemPresentation present(Item item) => ItemPresentation(
    headline: firstLine(item.content),
    openBehavior: OpenBehavior.detailView,
  );

  @override
  NoteDraft toNote(Item item, NoteContext context) => NoteDraft(
    title: firstLine(item.content),
    body: '${item.content.trimRight()}\n\n${noteFooter(item, context)}\n',
  );
}
