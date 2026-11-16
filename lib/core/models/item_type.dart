/// The kind of an [Item], stored on the wire as a plain string.
///
/// Unknown values are kept as-is instead of being rejected, so that items
/// written by a newer version of Specular can still be shown as generic
/// items (SPEC.md §5.2).
final class ItemType {
  const ItemType(this.wireName);

  /// The value of the `type` field in the item JSON.
  final String wireName;

  static const link = ItemType('link');
  static const text = ItemType('text');

  /// Reserved for v0.2.
  static const image = ItemType('image');

  /// Reserved for v0.2.
  static const file = ItemType('file');

  @override
  bool operator ==(Object other) =>
      other is ItemType && other.wireName == wireName;

  @override
  int get hashCode => wireName.hashCode;

  @override
  String toString() => 'ItemType($wireName)';
}
