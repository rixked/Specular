import 'dart:convert';

import 'attachment.dart';
import 'item_type.dart';
import 'json_utils.dart';

/// One thing that was sent: a link, a text snippet, or (v0.2+) a file.
///
/// Items are immutable, both in memory and on the server: devices only
/// create and delete item files, never edit them (SPEC.md §5.1).
final class Item {
  const Item({
    this.schema = currentSchema,
    required this.id,
    required this.type,
    required this.content,
    this.title,
    required this.createdAt,
    required this.sourceDevice,
    this.attachment,
  });

  /// Parses an item file. Unknown fields are ignored and unknown types are
  /// preserved. Throws [FormatException] if required fields are missing.
  factory Item.fromJson(Map<String, Object?> json) {
    final attachment = optionalField<Map<String, Object?>>(json, 'attachment');
    return Item(
      schema: optionalField<int>(json, 'schema') ?? currentSchema,
      id: requireField<String>(json, 'id'),
      type: ItemType(requireField<String>(json, 'type')),
      content: requireField<String>(json, 'content'),
      title: optionalField<String>(json, 'title'),
      createdAt: requireUtcDate(json, 'createdAt'),
      sourceDevice: requireField<String>(json, 'sourceDevice'),
      attachment: attachment == null ? null : Attachment.fromJson(attachment),
    );
  }

  /// Decodes the UTF-8 JSON text of an item file.
  factory Item.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Item file is not a JSON object', source);
    }
    return Item.fromJson(decoded);
  }

  static const currentSchema = 1;

  final int schema;

  /// `<UTC timestamp>-<deviceId>-<random>`; see `ItemIds`.
  final String id;
  final ItemType type;

  /// The URL for links, the text for text items.
  final String content;

  /// Optional display title, for example a link's page title.
  final String? title;

  /// When the sending device created the item (device clock, UTC).
  ///
  /// Used for display and ordering only. Expiry uses the server's
  /// modification time instead (SPEC.md §3.5).
  final DateTime createdAt;

  /// The device ID of the sender.
  final String sourceDevice;
  final Attachment? attachment;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'id': id,
    'type': type.wireName,
    'content': content,
    'title': title,
    'createdAt': formatUtcSeconds(createdAt),
    'sourceDevice': sourceDevice,
    'attachment': attachment?.toJson(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  @override
  bool operator ==(Object other) =>
      other is Item &&
      other.schema == schema &&
      other.id == id &&
      other.type == type &&
      other.content == content &&
      other.title == title &&
      other.createdAt == createdAt &&
      other.sourceDevice == sourceDevice &&
      other.attachment == attachment;

  @override
  int get hashCode => Object.hash(
    schema,
    id,
    type,
    content,
    title,
    createdAt,
    sourceDevice,
    attachment,
  );

  @override
  String toString() => 'Item($id, ${type.wireName})';
}
