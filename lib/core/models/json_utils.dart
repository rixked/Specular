/// Small helpers for strict-but-forward-compatible JSON parsing.
library;

T requireField<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Field "$key" is missing or not a $T', json);
}

T? optionalField<T>(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null) return null;
  if (value is T) return value as T;
  throw FormatException('Field "$key" is not a $T', json);
}

DateTime requireUtcDate(Map<String, Object?> json, String key) {
  final raw = requireField<String>(json, key);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('Field "$key" is not an ISO-8601 date', raw);
  }
  return parsed.toUtc();
}

/// Formats [time] as `2026-11-16T10:35:12Z` (UTC, second precision).
String formatUtcSeconds(DateTime time) {
  final t = time.toUtc();
  return '${_four(t.year)}-${_two(t.month)}-${_two(t.day)}'
      'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}Z';
}

/// Formats [time] as `20261116T103512Z` (UTC, compact, sortable).
String formatCompactUtc(DateTime time) {
  final t = time.toUtc();
  return '${_four(t.year)}${_two(t.month)}${_two(t.day)}'
      'T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
}

/// Formats the calendar date of [time] as `2026-11-16`, in [time]'s own zone.
String formatDate(DateTime time) =>
    '${_four(time.year)}-${_two(time.month)}-${_two(time.day)}';

String _two(int n) => n.toString().padLeft(2, '0');
String _four(int n) => n.toString().padLeft(4, '0');
