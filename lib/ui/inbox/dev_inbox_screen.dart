import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/sync_coordinator.dart';
import '../../core/item_types/item_type_handler.dart';
import '../../core/models/item.dart';
import '../../core/sync/local_store.dart';
import '../../core/sync/sync_engine.dart';
import '../common/url_opener.dart';

/// A bare-bones inbox for trying out sync before the real UI exists.
///
/// Shows the sync state, the items and a send field. Replaced by the real
/// inbox once the visual direction is chosen (SPEC.md §9, §13).
class DevInboxScreen extends StatefulWidget {
  const DevInboxScreen({
    super.key,
    required this.engine,
    required this.coordinator,
    required this.onLogOut,
    this.openUrl = openInBrowser,
  });

  final SyncEngine engine;
  final SyncCoordinator coordinator;
  final VoidCallback onLogOut;
  final UrlOpener openUrl;

  @override
  State<DevInboxScreen> createState() => _DevInboxScreenState();
}

class _DevInboxScreenState extends State<DevInboxScreen> {
  final _input = TextEditingController();
  late final Stream<List<LocalItem>> _inbox = widget.engine.watchInbox();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await widget.engine.send(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<SyncState>(
          stream: widget.coordinator.states,
          initialData: widget.coordinator.state,
          builder: (context, snapshot) =>
              Text('Specular · ${_describe(snapshot.data!)}'),
        ),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.coordinator.syncNow(force: true),
          ),
          TextButton(onPressed: widget.onLogOut, child: const Text('Log out')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<LocalItem>>(
              stream: _inbox,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const Center(child: Text('Nothing here yet.'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ItemTile(
                    local: items[i],
                    engine: widget.engine,
                    openUrl: widget.openUrl,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const Key('send'),
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Send a link or a note',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _describe(SyncState state) => switch (state.phase) {
    SyncPhase.stopped => 'starting',
    SyncPhase.syncing => 'syncing…',
    SyncPhase.idle => 'up to date',
    SyncPhase.offline => 'offline',
    SyncPhase.unauthorized => 'please log in again',
    SyncPhase.error => 'error: ${state.message ?? 'unknown'}',
  };
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.local,
    required this.engine,
    required this.openUrl,
  });

  final LocalItem local;
  final SyncEngine engine;
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    final item = local.item;
    final pending = local.status == SyncStatus.pending;
    final handler = engine.registry.handlerFor(item.type);
    return ListTile(
      onTap: () => _open(context, handler),
      title: Text(
        item.title ?? item.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.type.wireName} · ${pending ? 'pending' : 'synced'}'
        '${item.title != null ? ' · ${item.content}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('copy-${item.id}'),
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () => copyToClipboard(context, handler.copyText(item)),
          ),
          IconButton(
            tooltip: 'Keep',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => _run(context, () => engine.keep(item.id)),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _run(context, () => engine.delete(item.id)),
          ),
        ],
      ),
    );
  }

  /// Open (SPEC.md §3.4): links go to the browser, everything else to the
  /// detail view.
  Future<void> _open(BuildContext context, ItemTypeHandler handler) async {
    final item = local.item;
    if (handler.present(item).openBehavior == OpenBehavior.external) {
      final url = Uri.tryParse(item.content);
      if (url != null && await openUrl(url)) return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ItemDetailScreen(item: item, copyText: handler.copyText(item)),
      ),
    );
  }

  static Future<void> _run(
    BuildContext context,
    Future<Object?> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// Copies [text] and confirms with a short snackbar.
Future<void> copyToClipboard(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(
    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
  );
}

/// Shows an item in full, selectable, with a Copy action (SPEC.md §3.3).
class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({
    super.key,
    required this.item,
    required this.copyText,
  });

  final Item item;
  final String copyText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.title ?? item.type.wireName),
        actions: [
          IconButton(
            key: const Key('detail-copy'),
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () => copyToClipboard(context, copyText),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(item.content),
      ),
    );
  }
}
