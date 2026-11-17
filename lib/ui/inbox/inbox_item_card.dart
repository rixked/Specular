import 'package:material_ui/material_ui.dart';

import '../../core/item_types/item_type_handler.dart';
import '../../core/models/item_type.dart';
import '../../core/sync/local_store.dart';
import '../common/glass_card.dart';
import '../common/relative_time.dart';
import '../theme/tokens.dart';

/// One inbox item as a Soft Glass card (SPEC.md §3.3, §3.4, §9).
///
/// Collapsed it shows one line ending in "…"; expanded it shows the full
/// text (and a link's full URL) plus Open, Keep and Delete.
class InboxItemCard extends StatefulWidget {
  const InboxItemCard({
    super.key,
    required this.local,
    required this.handler,
    required this.now,
    required this.onOpen,
    required this.onCopy,
    required this.onKeep,
    required this.onDelete,
    this.deviceName,
    this.glint = false,
    this.onGlintDone,
  });

  final LocalItem local;
  final ItemTypeHandler handler;

  /// The current time, for the age shown and the fading sheen.
  final DateTime now;
  final String? deviceName;
  final bool glint;
  final VoidCallback? onGlintDone;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onKeep;
  final VoidCallback onDelete;

  @override
  State<InboxItemCard> createState() => _InboxItemCardState();
}

class _InboxItemCardState extends State<InboxItemCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final item = widget.local.item;
    final presentation = widget.handler.present(item);
    final isLink = presentation.openBehavior == OpenBehavior.external;
    final pending = widget.local.status == SyncStatus.pending;

    var age = widget.now.difference(
      widget.local.serverModified ?? item.createdAt,
    );
    if (age.isNegative) age = Duration.zero;

    final meta = [
      if (isLink && presentation.subtitle != null) presentation.subtitle!,
      widget.deviceName ?? item.sourceDevice,
      relativeAge(age),
      ?expiryHint(age),
    ].join(' · ');

    final fullTitle = isLink ? (item.title ?? item.content) : item.content;
    final showUrl = _expanded && isLink && item.title != null;
    final expandDuration = SpecularMotion.of(context, SpecularMotion.expand);

    return GlassCard(
      sheen: pending ? 1 : sheenForAge(age),
      glint: widget.glint,
      onGlintDone: widget.onGlintDone,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: isLink ? widget.onOpen : _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeTile(type: item.type, isLink: isLink),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSize(
                          duration: expandDuration,
                          alignment: Alignment.topLeft,
                          child: Text(
                            _expanded ? fullTitle : presentation.headline,
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
                        ),
                        if (showUrl) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.content,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: SpecularColors.icon,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              meta,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: SpecularColors.textSecondary,
                              ),
                            ),
                            if (pending) const _PendingPill(),
                          ],
                        ),
                        if (_expanded)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 4,
                              children: [
                                if (isLink)
                                  _ActionButton(
                                    icon: Icons.open_in_new_rounded,
                                    label: 'Open',
                                    onPressed: widget.onOpen,
                                  ),
                                _ActionButton(
                                  icon: Icons.bookmark_add_outlined,
                                  label: 'Keep',
                                  onPressed: widget.onKeep,
                                ),
                                _ActionButton(
                                  icon: Icons.delete_outline_rounded,
                                  label: 'Delete',
                                  onPressed: widget.onDelete,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _IconButton(
                  key: ValueKey('copy-${item.id}'),
                  tooltip: 'Copy',
                  icon: Icons.copy_rounded,
                  onPressed: widget.onCopy,
                ),
                _ExpandButton(
                  key: ValueKey('expand-${item.id}'),
                  expanded: _expanded,
                  onPressed: _toggle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.type, required this.isLink});

  final ItemType type;
  final bool isLink;

  @override
  Widget build(BuildContext context) {
    final icon = isLink
        ? Icons.link_rounded
        : type == ItemType.text
        ? Icons.notes_rounded
        : Icons.inventory_2_outlined;
    return ExcludeSemantics(
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SpecularRadii.iconTile),
        ),
        child: Icon(icon, size: 18, color: SpecularColors.icon),
      ),
    );
  }
}

class _PendingPill extends StatelessWidget {
  const _PendingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: SpecularColors.pendingBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 11,
            color: SpecularColors.pendingText,
          ),
          SizedBox(width: 4),
          Text(
            'Pending',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: SpecularColors.pendingText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: SpecularColors.text,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: SpecularColors.icon,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpecularRadii.button),
        ),
      ),
    );
  }
}

/// The chevron that expands and collapses a card.
class ExpandButtonIcon extends StatelessWidget {
  const ExpandButtonIcon({super.key, required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: SpecularMotion.of(context, SpecularMotion.expand),
      child: const Icon(Icons.expand_more_rounded, size: 22),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  const _ExpandButton({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: expanded ? 'Collapse' : 'Expand',
      onPressed: onPressed,
      icon: ExpandButtonIcon(expanded: expanded),
      color: SpecularColors.icon,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpecularRadii.button),
        ),
      ),
    );
  }
}
