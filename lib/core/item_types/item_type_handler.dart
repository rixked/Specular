import '../models/item.dart';
import '../models/item_type.dart';
import 'note_draft.dart';

/// User actions an item can offer (SPEC.md §3.4).
enum ItemAction { open, copy, keep, delete }

/// What [ItemAction.open] does for an item.
enum OpenBehavior {
  /// Open the content externally, for example a URL in the browser.
  external,

  /// Show the item in full in the detail view.
  detailView,
}

/// A platform-independent description of how to render an item.
///
/// `lib/core/` must not depend on Flutter, so handlers describe the
/// rendering and the UI layer turns this description into widgets.
final class ItemPresentation {
  const ItemPresentation({
    required this.headline,
    this.subtitle,
    required this.openBehavior,
  });

  /// Primary line, for example a page title or the first line of a text.
  final String headline;

  /// Secondary line, for example the link's domain.
  final String? subtitle;
  final OpenBehavior openBehavior;
}

/// Everything Specular needs to know about one item type
/// (SPEC.md §7, extension point 1).
///
/// New types plug into the `ItemTypeRegistry` without touching the core.
abstract class ItemTypeHandler {
  const ItemTypeHandler();

  ItemType get type;

  /// Whether raw user input (already trimmed, never empty) should become an
  /// item of this type.
  bool detects(String input);

  /// Actions shown for items of this type, in display order.
  List<ItemAction> get actions => const [
    ItemAction.open,
    ItemAction.copy,
    ItemAction.keep,
    ItemAction.delete,
  ];

  ItemPresentation present(Item item);

  /// The text that [ItemAction.copy] puts on the clipboard.
  String copyText(Item item) => item.content;

  /// Converts the item to a permanent note (SPEC.md §5.3).
  NoteDraft toNote(Item item, NoteContext context);
}
