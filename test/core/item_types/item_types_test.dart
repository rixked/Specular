import 'package:flutter_test/flutter_test.dart';
import 'package:specular/core/item_types/generic_handler.dart';
import 'package:specular/core/item_types/item_type_handler.dart';
import 'package:specular/core/item_types/item_type_registry.dart';
import 'package:specular/core/item_types/link_handler.dart';
import 'package:specular/core/item_types/note_draft.dart';
import 'package:specular/core/item_types/text_handler.dart';
import 'package:specular/core/models/item.dart';
import 'package:specular/core/models/item_type.dart';

Item _item(ItemType type, String content, {String? title}) => Item(
  id: '20261116T120000Z-a1b2c3-000000',
  type: type,
  content: content,
  title: title,
  createdAt: DateTime.utc(2026, 11, 16, 12),
  sourceDevice: 'a1b2c3',
);

const _context = NoteContext(deviceName: 'Pixel');

void main() {
  final registry = ItemTypeRegistry.standard();

  group('classify (SPEC.md §3.2)', () {
    test('a message containing only a URL is a link', () {
      expect(
        registry.classify('https://www.tiktok.com/@user/video/123'),
        ItemType.link,
      );
      expect(
        registry.classify('  http://example.com/a?b=c#d \n'),
        ItemType.link,
      );
      expect(registry.classify('https://vm.tiktok.com/ZMabc/'), ItemType.link);
    });

    test('anything else is text', () {
      expect(
        registry.classify('Look at this https://example.com'),
        ItemType.text,
      );
      expect(registry.classify('example.com'), ItemType.text);
      expect(registry.classify('ftp://example.com/file'), ItemType.text);
      expect(registry.classify('mailto:me@example.com'), ItemType.text);
      expect(registry.classify('https://'), ItemType.text);
      expect(registry.classify('hello\nworld'), ItemType.text);
    });

    test('blank input is rejected', () {
      expect(() => registry.classify('   '), throwsArgumentError);
    });
  });

  group('registry', () {
    test('unknown types fall back to the generic handler', () {
      expect(
        registry.handlerFor(const ItemType('hologram')),
        isA<GenericHandler>(),
      );
      expect(registry.handlerFor(ItemType.link), isA<LinkHandler>());
      expect(registry.handlerFor(ItemType.text), isA<TextHandler>());
    });

    test('rejects duplicate handlers', () {
      expect(
        () => ItemTypeRegistry(const [TextHandler(), TextHandler()]),
        throwsArgumentError,
      );
    });

    test('every type offers Open, Copy, Keep and Delete', () {
      for (final handler in [...registry.handlers, registry.fallback]) {
        expect(handler.actions, ItemAction.values);
      }
    });
  });

  group('presentation', () {
    test('links open externally and show their domain', () {
      final p = const LinkHandler().present(
        _item(ItemType.link, 'https://www.youtube.com/watch?v=1'),
      );
      expect(p.openBehavior, OpenBehavior.external);
      expect(p.headline, 'https://www.youtube.com/watch?v=1');
      expect(p.subtitle, 'youtube.com');
    });

    test('text opens in the detail view', () {
      final p = const TextHandler().present(
        _item(ItemType.text, '\n  Hi\nthere'),
      );
      expect(p.openBehavior, OpenBehavior.detailView);
      expect(p.headline, 'Hi');
    });

    test('unknown types are shown generically', () {
      final p = registry
          .handlerFor(const ItemType('hologram'))
          .present(_item(const ItemType('hologram'), 'beam me up'));
      expect(p.headline, 'beam me up');
      expect(p.subtitle, 'hologram');
      expect(p.openBehavior, OpenBehavior.detailView);
    });
  });

  group('notes (SPEC.md §5.3)', () {
    test('link with page title uses the title', () {
      final note = const LinkHandler().toNote(
        _item(ItemType.link, 'https://example.com/a', title: 'A Page'),
        _context,
      );
      expect(note.title, 'A Page');
      expect(
        note.body,
        'https://example.com/a\n\nSent from Pixel · 2026-11-16\n',
      );
    });

    test('link without title uses domain plus date', () {
      final note = const LinkHandler().toNote(
        _item(ItemType.link, 'https://www.tiktok.com/@user/video/123'),
        _context,
      );
      expect(note.title, 'tiktok.com 2026-11-16');
    });

    test('text uses its first line, truncated to ~60 characters', () {
      final long = 'x' * 100;
      expect(
        const TextHandler()
            .toNote(_item(ItemType.text, '\n\nShopping list\nmilk'), _context)
            .title,
        'Shopping list',
      );
      expect(
        const TextHandler()
            .toNote(_item(ItemType.text, '$long\nmore'), _context)
            .title,
        'x' * 60,
      );
    });

    test('text body is the content plus the footer', () {
      final note = const TextHandler().toNote(
        _item(ItemType.text, 'line 1\nline 2\n\n'),
        _context,
      );
      expect(note.body, 'line 1\nline 2\n\nSent from Pixel · 2026-11-16\n');
    });

    test('truncation does not split emoji', () {
      final text = '${'a' * 59}😀😀';
      final title = TextHandler.firstLine(text);
      expect(title, '${'a' * 59}😀');
    });
  });

  group('note file names', () {
    test('strips invalid characters', () {
      expect(sanitizeNoteTitle('a/b\\c:d*e?f"g<h>i|j'), 'abcdefghij');
      expect(sanitizeNoteTitle('tab\there\nnewline'), 'tab here newline');
      expect(sanitizeNoteTitle('  trailing dots... '), 'trailing dots');
      expect(sanitizeNoteTitle('.hidden'), 'hidden');
    });

    test('falls back for empty or reserved names', () {
      expect(sanitizeNoteTitle('???'), 'Note');
      expect(sanitizeNoteTitle(''), 'Note');
      expect(sanitizeNoteTitle('con'), 'Note con');
    });

    test('appends (2), (3), … on a clash, case-insensitively', () {
      expect(noteFileName('Ideas', const []), 'Ideas.md');
      expect(noteFileName('Ideas', const ['ideas.md']), 'Ideas (2).md');
      expect(
        noteFileName('Ideas', const ['Ideas.md', 'Ideas (2).md']),
        'Ideas (3).md',
      );
    });
  });
}
