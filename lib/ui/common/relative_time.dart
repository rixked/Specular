import '../theme/tokens.dart';

/// "just now", "2 min", "3 h", "1 day", "3 days".
String relativeAge(Duration age) {
  if (age < const Duration(minutes: 1)) return 'just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes} min';
  if (age < const Duration(days: 1)) return '${age.inHours} h';
  final days = age.inDays;
  return days == 1 ? '1 day' : '$days days';
}

/// "expires today" / "expires tomorrow" near the end of an item's
/// 7-day life, otherwise null.
String? expiryHint(Duration age) {
  final remaining = itemLifetime - age;
  if (remaining < const Duration(days: 1)) return 'expires today';
  if (remaining < const Duration(days: 2)) return 'expires tomorrow';
  return null;
}

/// "kept just now", "kept 3 h ago", "kept yesterday", "kept 4 days ago",
/// "kept last week", "kept 3 weeks ago".
String keptAgo(Duration age) {
  if (age < const Duration(minutes: 1)) return 'kept just now';
  if (age < const Duration(days: 1)) return 'kept ${relativeAge(age)} ago';
  final days = age.inDays;
  if (days == 1) return 'kept yesterday';
  if (days < 7) return 'kept $days days ago';
  if (days < 14) return 'kept last week';
  return 'kept ${days ~/ 7} weeks ago';
}
