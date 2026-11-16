import '../models/item.dart';
import '../models/item_type.dart';
import 'item_type_handler.dart';
import 'note_draft.dart';
import 'text_handler.dart';

/// Fallback for item types this version does not know, so that items from
/// newer versions are shown instead of crashing the app (SPEC.md §5.2).
final class GenericHandler extends ItemTypeHandler {
  const GenericHandler();

  @override
  ItemType get type => const ItemType('*');

  /// Never chosen for user input.
  @override
  bool detects(String input) => false;

  @override
  ItemPresentation present(Item item) {
    final title = item.title?.trim();
    return ItemPresentation(
      headline: (title != null && title.isNotEmpty)
          ? title
          : TextHandler.firstLine(item.content),
      subtitle: item.type.wireName,
      openBehavior: OpenBehavior.detailView,
    );
  }

  @override
  NoteDraft toNote(Item item, NoteContext context) {
    final title = item.title?.trim();
    return NoteDraft(
      title: (title != null && title.isNotEmpty)
          ? title
          : TextHandler.firstLine(item.content),
      body: '${item.content.trimRight()}\n\n${noteFooter(item, context)}\n',
    );
  }
}
