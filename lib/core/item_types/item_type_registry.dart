import '../models/item_type.dart';
import 'generic_handler.dart';
import 'item_type_handler.dart';
import 'link_handler.dart';
import 'text_handler.dart';

/// Maps item types to their handlers and classifies user input.
final class ItemTypeRegistry {
  /// [handlers] are consulted in order by [classify], so put specific types
  /// (like links) before catch-all types (like text).
  ItemTypeRegistry(
    List<ItemTypeHandler> handlers, {
    this.fallback = const GenericHandler(),
  }) : _handlers = List.unmodifiable(handlers) {
    final types = <ItemType>{};
    for (final handler in _handlers) {
      if (!types.add(handler.type)) {
        throw ArgumentError('Duplicate handler for ${handler.type}');
      }
    }
  }

  /// The v0.1 registry: `link`, then `text`.
  factory ItemTypeRegistry.standard() =>
      ItemTypeRegistry(const [LinkHandler(), TextHandler()]);

  final List<ItemTypeHandler> _handlers;

  /// Used for unknown types.
  final ItemTypeHandler fallback;

  List<ItemTypeHandler> get handlers => _handlers;

  ItemTypeHandler handlerFor(ItemType type) {
    for (final handler in _handlers) {
      if (handler.type == type) return handler;
    }
    return fallback;
  }

  /// The type that trimmed, non-empty [input] should be sent as.
  ///
  /// Throws [ArgumentError] if no handler accepts the input.
  ItemType classify(String input) {
    final trimmed = input.trim();
    for (final handler in _handlers) {
      if (handler.detects(trimmed)) return handler.type;
    }
    throw ArgumentError.value(input, 'input', 'No item type accepts this');
  }
}
