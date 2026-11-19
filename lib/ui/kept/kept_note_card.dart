import 'package:material_ui/material_ui.dart';

import '../../core/item_types/link_handler.dart';
import '../../core/sync/sync_engine.dart';
import '../common/glass_card.dart';
import '../common/relative_time.dart';
import '../inbox/inbox_item_card.dart' show ExpandButtonIcon;
import '../theme/tokens.dart';

/// A kept note in the Kept view: always with the prism edge (SPEC.md §3.4.1,
/// §9). Expanding it loads and shows the whole note.
class KeptNoteCard extends StatefulWidget {
  const KeptNoteCard({
    super.key,
    required this.note,
    required this.now,
    required this.loadBody,
    required this.onCopy,
    required this.onOpenUrl,
    required this.onDelete,
  });

  final KeptNote note;
  final DateTime now;
  final Future<String> Function() loadBody;
  final void Function(String text) onCopy;
  final void Function(Uri url) onOpenUrl;
  final VoidCallback onDelete;

  @override
  State<KeptNoteCard> createState() => _KeptNoteCardState();
}

class _KeptNoteCardState extends State<KeptNoteCard> {
  bool _expanded = false;
  Future<String>? _body;

  Future<String> _loadBody() =>
      _body ??= widget.loadBody()
        ..catchError((Object _) {
          // Allow a retry on the next expand.
          _body = null;
          return '';
        });

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) _loadBody();
    });
  }

  Future<void> _copy() async {
    try {
      widget.onCopy(await _loadBody());
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't load this note.")));
    }
  }

  static Uri? _linkIn(String body) {
    final firstLine = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return LinkHandler.parse(firstLine);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final modified = note.lastModified;
    final meta = modified == null
        ? 'kept'
        : keptAgo(widget.now.difference(modified).abs());

    return GlassCard(
      prism: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        SpecularRadii.iconTile,
                      ),
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      size: 18,
                      color: SpecularColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title,
                          maxLines: _expanded ? null : 1,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        AnimatedSize(
                          duration: SpecularMotion.of(
                            context,
                            SpecularMotion.expand,
                          ),
                          alignment: Alignment.topLeft,
                          child: _expanded
                              ? _NoteBody(
                                  body: _loadBody(),
                                  onOpenUrl: widget.onOpenUrl,
                                  linkIn: _linkIn,
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: SpecularColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('copy-kept-${note.fileName}'),
                  tooltip: 'Copy',
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: SpecularColors.icon,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                ),
                IconButton(
                  key: ValueKey('delete-kept-${note.fileName}'),
                  tooltip: 'Delete',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: SpecularColors.icon,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                ),
                IconButton(
                  key: ValueKey('expand-kept-${note.fileName}'),
                  tooltip: _expanded ? 'Collapse' : 'Expand',
                  onPressed: _toggle,
                  icon: ExpandButtonIcon(expanded: _expanded),
                  color: SpecularColors.icon,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody({
    required this.body,
    required this.onOpenUrl,
    required this.linkIn,
  });

  final Future<String> body;
  final void Function(Uri url) onOpenUrl;
  final Uri? Function(String body) linkIn;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: body,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              "Couldn't load this note. Check your connection.",
              style: TextStyle(fontSize: 13, color: SpecularColors.error),
            ),
          );
        }
        final text = snapshot.data;
        if (text == null) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final link = linkIn(text);
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                text.trimRight(),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: SpecularColors.icon,
                ),
              ),
              if (link != null)
                TextButton.icon(
                  onPressed: () => onOpenUrl(link),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open link'),
                  style: TextButton.styleFrom(
                    foregroundColor: SpecularColors.text,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
