import 'json_utils.dart';

/// A file attached to an item (v0.2+, SPEC.md §5.2).
final class Attachment {
  const Attachment({
    required this.path,
    required this.mime,
    required this.size,
  });

  factory Attachment.fromJson(Map<String, Object?> json) => Attachment(
    path: requireField<String>(json, 'path'),
    mime: requireField<String>(json, 'mime'),
    size: requireField<int>(json, 'size'),
  );

  /// Path relative to `/Specular/`, for example `files/<itemId>/photo.jpg`.
  final String path;
  final String mime;
  final int size;

  Map<String, Object?> toJson() => {'path': path, 'mime': mime, 'size': size};

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      other.path == path &&
      other.mime == mime &&
      other.size == size;

  @override
  int get hashCode => Object.hash(path, mime, size);
}
