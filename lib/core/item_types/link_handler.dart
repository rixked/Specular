import '../models/item.dart';
import '../models/item_type.dart';
import '../models/json_utils.dart';
import 'item_type_handler.dart';
import 'note_draft.dart';

/// Handles `link` items: a message that consists of a single http(s) URL.
final class LinkHandler extends ItemTypeHandler {
  const LinkHandler();

  /// Parses [input] as a link, or returns null if it is not exactly one
  /// http(s) URL with a host.
  static Uri? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// The host without a leading `www.`, or the raw content if unparsable.
  static String domainOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  @override
  ItemType get type => ItemType.link;

  @override
  bool detects(String input) => parse(input) != null;

  @override
  ItemPresentation present(Item item) {
    final title = item.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    return ItemPresentation(
      headline: hasTitle ? title : item.content,
      subtitle: domainOf(item.content),
      openBehavior: OpenBehavior.external,
    );
  }

  @override
  NoteDraft toNote(Item item, NoteContext context) {
    final pageTitle = item.title?.trim();
    final title = (pageTitle != null && pageTitle.isNotEmpty)
        ? pageTitle
        : '${domainOf(item.content)} ${formatDate(item.createdAt.toLocal())}';
    return NoteDraft(
      title: title,
      body: '${item.content}\n\n${noteFooter(item, context)}\n',
    );
  }
}
