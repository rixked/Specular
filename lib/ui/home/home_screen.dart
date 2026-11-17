import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/sync_coordinator.dart';
import '../../backends/storage_backend.dart';
import '../../core/models/item.dart';
import '../../core/sync/local_store.dart';
import '../../core/sync/sync_engine.dart';
import '../common/glass_toast.dart';
import '../common/specular_background.dart';
import '../common/url_opener.dart';
import '../inbox/inbox_item_card.dart';
import '../kept/kept_note_card.dart';
import '../../platform/updater/update_service.dart';
import '../theme/tokens.dart';
import '../update/update_controller.dart';

enum HomeTab { inbox, kept }

/// The main screen (SPEC.md §3, §9): Inbox and Kept, the send field and
/// the "Sent" confirmation, in the Soft Glass look.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.engine,
    required this.coordinator,
    required this.onLogOut,
    this.openUrl = openInBrowser,
    this.clock = DateTime.now,
    this.updates,
  });

  /// Null where Specular has no releases.
  final UpdateController? updates;

  final SyncEngine engine;
  final SyncCoordinator coordinator;
  final VoidCallback onLogOut;
  final UrlOpener openUrl;
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode(debugLabel: 'send field');
  StreamSubscription<List<LocalItem>>? _inboxSub;
  List<LocalItem>? _items;
  StreamSubscription<List<Item>>? _received;
  Timer? _clockTick;
  Timer? _toastTimer;

  HomeTab _tab = HomeTab.inbox;
  bool _showSent = false;
  Map<String, String> _deviceNames = const {};
  final _glintIds = <String>{};

  /// Items hidden while "Deleted · Undo" is showing.
  final _pendingDeletes = <String>{};
  static const _undoWindow = Duration(seconds: 4);

  List<KeptNote>? _kept;
  Object? _keptError;
  bool _keptLoading = false;

  SyncEngine get _engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _inboxSub = _engine.watchInbox().listen(
      (items) => setState(() => _items = items),
    );
    _received = _engine.received.listen((items) {
      setState(() => _glintIds.addAll(items.map((i) => i.id)));
      unawaited(_loadDeviceNames());
    });
    // Refresh relative times ("2 min") and the fading sheen.
    _clockTick = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
    unawaited(_loadDeviceNames());
    unawaited(_loadKept());
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _inputFocus.dispose();
    unawaited(_inboxSub?.cancel());
    unawaited(_received?.cancel());
    _clockTick?.cancel();
    _toastTimer?.cancel();
    _input.dispose();
    // Leaving the screen (e.g. closing the app) confirms pending deletes.
    for (final id in _pendingDeletes.toList()) {
      unawaited(_engine.delete(id).catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _loadDeviceNames() async {
    try {
      final names = await _engine.deviceNames();
      if (mounted) setState(() => _deviceNames = names);
    } on Object {
      // Names are cosmetic; device IDs are shown instead.
    }
  }

  Future<void> _loadKept() async {
    if (_keptLoading) return;
    setState(() => _keptLoading = true);
    try {
      final kept = await _engine.keptNotes();
      if (mounted) {
        setState(() {
          _kept = kept;
          _keptError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _keptError = e);
    } finally {
      if (mounted) setState(() => _keptLoading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    // Leave the field, so the next Ctrl+V sends right away again.
    _inputFocus.unfocus();
    await _sendText(text);
  }

  /// Ctrl+V (Cmd+V) anywhere in the window sends the clipboard right away
  /// (SPEC.md §3.2), wherever the focus is, unless a text field is being
  /// edited: then the key goes to the field's own paste.
  ///
  /// A global keyboard handler instead of a focus-based shortcut, because
  /// clicking around can move the focus out of this screen's subtree.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (_isEditingText()) return false;
    unawaited(_pasteAndSend());
    return true;
  }

  static bool _isEditingText() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> _pasteAndSend() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    unawaited(HapticFeedback.lightImpact());
    await _engine.send(text);
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _showSent = true);
    _toastTimer = Timer(SpecularMotion.toastVisible, () {
      if (mounted) setState(() => _showSent = false);
    });
  }

  Future<void> _copy(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _openUrl(Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await widget.openUrl(url)) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the browser.")),
      );
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(
        SnackBar(content: Text(done), duration: const Duration(seconds: 2)),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_describeError(e))));
    }
  }

  /// The manual check from the menu: always reports its outcome.
  Future<void> _checkForUpdates() async {
    final updates = widget.updates;
    if (updates == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await updates.check();
    final message = switch (result) {
      UpdateAvailable(:final release) =>
        'Update available: v${release.version}',
      UpToDate() => "You're up to date (v${updates.currentVersion})",
      UpdateCheckFailed(:final message) =>
        "Couldn't check for updates: $message",
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  static String _describeError(Object e) => switch (e) {
    StorageUnavailableException() =>
      "You're offline. Try again when connected.",
    StorageUnauthorizedException() =>
      'Nextcloud rejected the app password. Please log in again.',
    StorageException(:final message) => 'Something went wrong: $message',
    _ => 'Something went wrong.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpecularColors.background,
      body: SpecularBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _Header(
                    coordinator: widget.coordinator,
                    onSyncNow: () {
                      unawaited(widget.coordinator.syncNow(force: true));
                      unawaited(_loadKept());
                    },
                    onLogOut: widget.onLogOut,
                    updates: widget.updates,
                    onCheckUpdates: _checkForUpdates,
                  ),
                  _Tabs(
                    tab: _tab,
                    inboxCount: _items?.length,
                    keptCount: _kept?.length,
                    onSelect: (tab) {
                      setState(() => _tab = tab);
                      if (tab == HomeTab.kept) unawaited(_loadKept());
                    },
                  ),
                  Expanded(
                    child: switch (_tab) {
                      HomeTab.inbox => _buildInbox(),
                      HomeTab.kept => _buildKept(),
                    },
                  ),
                  _SendBar(
                    controller: _input,
                    focusNode: _inputFocus,
                    onSend: _send,
                  ),
                ],
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 88,
                child: Center(child: GlassToast.sent(visible: _showSent)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hides the item right away and shows "Deleted · Undo". Only when the
  /// bar closes without Undo is the item deleted on all devices.
  void _deleteWithUndo(String id) {
    if (!_pendingDeletes.add(id)) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final bar = messenger.showSnackBar(
      SnackBar(
        content: const Text('Deleted'),
        duration: _undoWindow,
        // Snack bars with an action stay until dismissed by default; this
        // one must close on its own so the delete goes through.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          textColor: SpecularColors.accent,
          onPressed: () {},
        ),
      ),
    );
    unawaited(
      bar.closed.then((reason) async {
        if (reason == SnackBarClosedReason.action) {
          _pendingDeletes.remove(id);
          if (mounted) setState(() {});
          return;
        }
        await _commitDelete(id);
      }),
    );
  }

  Future<void> _commitDelete(String id) async {
    if (!_pendingDeletes.contains(id)) return;
    try {
      await _engine.delete(id);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_describeError(e))));
      }
    } finally {
      _pendingDeletes.remove(id);
      if (mounted) setState(() {});
    }
  }

  Widget _buildInbox() {
    final items = [
      for (final local in _items ?? const <LocalItem>[])
        if (!_pendingDeletes.contains(local.id)) local,
    ];
    if (items.isEmpty) {
      return const _EmptyState(
        'Nothing here yet.\nShare something from another device.',
      );
    }
    final now = widget.clock();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final local = items[i];
        final item = local.item;
        final handler = _engine.registry.handlerFor(item.type);
        return Dismissible(
          key: ValueKey('dismiss-${item.id}'),
          onDismissed: (_) => _deleteWithUndo(item.id),
          background: const _SwipeToDelete(alignment: Alignment.centerLeft),
          secondaryBackground: const _SwipeToDelete(
            alignment: Alignment.centerRight,
          ),
          child: InboxItemCard(
            key: ValueKey(item.id),
            local: local,
            handler: handler,
            now: now,
            deviceName: item.sourceDevice == _engine.deviceId
                ? 'this device'
                : _deviceNames[item.sourceDevice],
            glint: _glintIds.contains(item.id),
            onGlintDone: () => setState(() => _glintIds.remove(item.id)),
            onOpen: () {
              final url = Uri.tryParse(item.content);
              if (url != null) unawaited(_openUrl(url));
            },
            onCopy: () => _copy(handler.copyText(item)),
            onKeep: () => _run(() async {
              await _engine.keep(item.id);
              await _loadKept();
            }, 'Kept · Notes › Specular'),
            onDelete: () => _deleteWithUndo(item.id),
          ),
        );
      },
    );
  }

  Widget _buildKept() {
    final kept = _kept;
    if (kept == null) {
      if (_keptError != null) {
        return const _EmptyState(
          "Couldn't load kept notes.\nThey need a connection to your Nextcloud.",
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Saved permanently in Nextcloud · Notes › Specular',
            style: TextStyle(
              fontSize: 12.5,
              color: SpecularColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: kept.isEmpty
              ? const _EmptyState(
                  'Nothing kept yet.\n'
                  'Expand an item and tap Keep to save it permanently.',
                )
              : RefreshIndicator(
                  onRefresh: _loadKept,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: kept.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final note = kept[i];
                      return KeptNoteCard(
                        key: ValueKey(note.fileName),
                        note: note,
                        now: widget.clock(),
                        loadBody: () => _engine.readKeptNote(note.fileName),
                        onCopy: _copy,
                        onOpenUrl: _openUrl,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// What appears behind a card while it is swiped away.
class _SwipeToDelete extends StatelessWidget {
  const _SwipeToDelete({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: SpecularColors.error.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(SpecularRadii.card),
      ),
      child: const Icon(
        Icons.delete_outline_rounded,
        color: SpecularColors.error,
        semanticLabel: 'Delete',
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.coordinator,
    required this.onSyncNow,
    required this.onLogOut,
    this.updates,
    this.onCheckUpdates,
  });

  final SyncCoordinator coordinator;
  final VoidCallback onSyncNow;
  final VoidCallback onLogOut;
  final UpdateController? updates;
  final VoidCallback? onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Expanded(
            child: Text(
              'Specular',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
          ),
          StreamBuilder<SyncState>(
            stream: coordinator.states,
            initialData: coordinator.state,
            builder: (context, snapshot) =>
                _SyncStatus(state: snapshot.data ?? coordinator.state),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(
              Icons.more_vert_rounded,
              color: SpecularColors.icon,
            ),
            onSelected: (value) => switch (value) {
              'sync' => onSyncNow(),
              'updates' => onCheckUpdates?.call(),
              'auto-updates' => unawaited(
                updates?.setAutoCheck(!(updates?.autoCheck.value ?? true)),
              ),
              'logout' => onLogOut(),
              _ => null,
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'sync', child: Text('Sync now')),
              if (updates case final updates?) ...[
                const PopupMenuItem(
                  value: 'updates',
                  child: Text('Check for updates'),
                ),
                CheckedPopupMenuItem(
                  value: 'auto-updates',
                  checked: updates.autoCheck.value,
                  child: const Text('Check automatically'),
                ),
              ],
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state.phase) {
      SyncPhase.stopped => ('Starting', SpecularColors.textSecondary),
      SyncPhase.syncing => ('Syncing…', SpecularColors.accent),
      SyncPhase.idle => ('Up to date', SpecularColors.accent),
      SyncPhase.offline => ('Offline', SpecularColors.textSecondary),
      SyncPhase.unauthorized => ('Log in again', SpecularColors.error),
      SyncPhase.error => ('Sync problem', SpecularColors.error),
    };
    return Tooltip(
      message: state.message ?? label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color, blurRadius: 10)],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: SpecularColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tab,
    required this.inboxCount,
    required this.keptCount,
    required this.onSelect,
  });

  final HomeTab tab;
  final int? inboxCount;
  final int? keptCount;
  final ValueChanged<HomeTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _TabButton(
            key: const Key('tab-inbox'),
            label: 'Inbox',
            count: inboxCount,
            selected: tab == HomeTab.inbox,
            onTap: () => onSelect(HomeTab.inbox),
          ),
          const SizedBox(width: 6),
          _TabButton(
            key: const Key('tab-kept'),
            label: 'Kept',
            count: keptCount,
            selected: tab == HomeTab.kept,
            onTap: () => onSelect(HomeTab.kept),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: 0.09)
            : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? SpecularColors.text
                        : SpecularColors.textSecondary,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SpecularColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            // Esc or a click elsewhere leaves the field, so Ctrl+V sends
            // directly again.
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    focusNode.unfocus,
              },
              child: TextField(
                key: const Key('send'),
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                onTapOutside: (_) => focusNode.unfocus(),
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Send a link or a note',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Send',
            child: Material(
              color: SpecularColors.accent,
              borderRadius: BorderRadius.circular(SpecularRadii.control),
              child: InkWell(
                key: const Key('send-button'),
                borderRadius: BorderRadius.circular(SpecularRadii.control),
                onTap: onSend,
                child: const SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: SpecularColors.onAccent,
                    semanticLabel: 'Send',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: SpecularColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
