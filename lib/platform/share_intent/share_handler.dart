import 'dart:async';

import '../../core/item_types/link_handler.dart';
import '../../core/models/item.dart';
import '../../core/sync/sync_engine.dart';

/// What another app handed over through the system Share menu.
final class SharePayload {
  const SharePayload({this.text, this.subject});

  factory SharePayload.fromMap(Map<Object?, Object?>? map) => SharePayload(
    text: map?['text'] as String?,
    subject: map?['subject'] as String?,
  );

  /// `EXTRA_TEXT`: usually the URL, sometimes a message.
  final String? text;

  /// `EXTRA_SUBJECT`: browsers put the page title here.
  final String? subject;
}

enum ShareOutcome {
  /// Stored locally (and usually uploaded already).
  sent,

  /// The user hasn't logged in yet.
  notLoggedIn,

  /// The share contained no text.
  nothingToSend,

  /// Storing the item failed.
  failed,
}

/// Turns a share into a queued item (SPEC.md §3.2).
///
/// Returns as soon as the item is stored locally, so the "Sent"
/// confirmation can show right away. Upload separately with [uploadShared].
Future<({ShareOutcome outcome, Item? item})> handleShare(
  SharePayload payload,
  SyncEngine? engine,
) async {
  final text = payload.text?.trim() ?? '';
  final subject = payload.subject?.trim() ?? '';
  final content = text.isNotEmpty ? text : subject;
  if (content.isEmpty) return (outcome: ShareOutcome.nothingToSend, item: null);
  if (engine == null) return (outcome: ShareOutcome.notLoggedIn, item: null);

  // A shared link keeps the page title the browser sent along; it becomes
  // the note title on Keep (SPEC.md §5.3).
  final isLink = LinkHandler.parse(content) != null;
  final title = isLink && subject.isNotEmpty && subject != content
      ? subject
      : null;

  try {
    final item = await engine.enqueue(content, title: title);
    return (outcome: ShareOutcome.sent, item: item);
  } on Object {
    return (outcome: ShareOutcome.failed, item: null);
  }
}

/// Tries to upload right away, but gives up after [timeout] so the share
/// window never lingers. Anything left stays queued and goes out on the
/// next sync.
Future<void> uploadShared(
  SyncEngine engine, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    await engine.uploadPending().timeout(timeout);
  } on TimeoutException {
    // Still queued.
  }
}
