import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:specular/core/models/attachment.dart';
import 'package:specular/core/models/device.dart';
import 'package:specular/core/models/item.dart';
import 'package:specular/core/models/item_ids.dart';
import 'package:specular/core/models/item_type.dart';

void main() {
  group('Item JSON', () {
    const specExample = '''
{
  "schema": 1,
  "id": "20261116T103512Z-a1b2c3-7f9e2d",
  "type": "link",
  "content": "https://www.tiktok.com/@user/video/123",
  "title": null,
  "createdAt": "2026-11-16T10:35:12Z",
  "sourceDevice": "a1b2c3",
  "attachment": null
}''';

    test('parses the example from SPEC.md §5.2', () {
      final item = Item.decode(specExample);
      expect(item.schema, 1);
      expect(item.id, '20261116T103512Z-a1b2c3-7f9e2d');
      expect(item.type, ItemType.link);
      expect(item.content, 'https://www.tiktok.com/@user/video/123');
      expect(item.title, isNull);
      expect(item.createdAt, DateTime.utc(2026, 11, 16, 10, 35, 12));
      expect(item.sourceDevice, 'a1b2c3');
      expect(item.attachment, isNull);
    });

    test('round-trips and writes the documented field format', () {
      final item = Item.decode(specExample);
      expect(Item.decode(item.encode()), item);
      expect(item.toJson()['createdAt'], '2026-11-16T10:35:12Z');
      expect(item.toJson().keys, [
        'schema', 'id', 'type', 'content', 'title', 'createdAt', //
        'sourceDevice', 'attachment',
      ]);
    });

    test('ignores unknown fields and accepts newer schemas', () {
      final item = Item.decode('''
{"schema": 7, "id": "20261116T103512Z-a1b2c3-7f9e2d", "type": "text",
 "content": "hi", "createdAt": "2026-11-16T10:35:12Z",
 "sourceDevice": "a1b2c3", "futureField": {"x": 1}}''');
      expect(item.schema, 7);
      expect(item.content, 'hi');
    });

    test('preserves unknown types', () {
      final item = Item.decode(
        '''
{"schema": 1, "id": "20261116T103512Z-a1b2c3-7f9e2d", "type": "hologram",
 "content": "?", "createdAt": "2026-11-16T10:35:12Z", "sourceDevice": "a1b2c3"}''',
      );
      expect(item.type, const ItemType('hologram'));
      expect(item.toJson()['type'], 'hologram');
    });

    test('parses attachments', () {
      final item = Item.decode(
        '''
{"schema": 1, "id": "20261116T103512Z-a1b2c3-7f9e2d", "type": "image",
 "content": "", "createdAt": "2026-11-16T10:35:12Z", "sourceDevice": "a1b2c3",
 "attachment": {"path": "files/x/a.jpg", "mime": "image/jpeg", "size": 1234}}''',
      );
      expect(
        item.attachment,
        const Attachment(path: 'files/x/a.jpg', mime: 'image/jpeg', size: 1234),
      );
    });

    test('rejects malformed files with FormatException', () {
      expect(() => Item.decode('not json'), throwsFormatException);
      expect(() => Item.decode('[1, 2]'), throwsFormatException);
      expect(() => Item.decode('{"id": "x"}'), throwsFormatException);
      expect(
        () => Item.decode('''
{"id": "x", "type": "text", "content": "a", "createdAt": "yesterday",
 "sourceDevice": "a"}'''),
        throwsFormatException,
      );
    });
  });

  group('Device JSON', () {
    test('round-trips', () {
      final device = Device(
        id: 'a1b2c3',
        name: 'Arch PC',
        platform: 'linux',
        lastSeen: DateTime.utc(2026, 11, 16, 9),
      );
      final decoded = Device.decode(device.encode());
      expect(decoded.id, 'a1b2c3');
      expect(decoded.name, 'Arch PC');
      expect(decoded.platform, 'linux');
      expect(decoded.lastSeen, DateTime.utc(2026, 11, 16, 9));
    });
  });

  group('ItemIds', () {
    test('generates <UTC timestamp>-<deviceId>-<random>', () {
      final id = ItemIds.generate(
        now: DateTime.utc(2026, 11, 16, 10, 35, 12),
        deviceId: 'a1b2c3',
        random: Random(1),
      );
      expect(id, matches(RegExp(r'^20261116T103512Z-a1b2c3-[0-9a-f]{6}$')));
      expect(ItemIds.isValid(id), isTrue);
    });

    test('converts local times to UTC', () {
      final local = DateTime.utc(2026, 11, 16, 10, 35, 12).toLocal();
      final id = ItemIds.generate(now: local, deviceId: 'a1b2c3');
      expect(id, startsWith('20261116T103512Z-'));
    });

    test('sorts by time', () {
      final ids = [
        for (final hour in [3, 1, 2])
          ItemIds.generate(
            now: DateTime.utc(2026, 1, 1, hour),
            deviceId: 'abc',
          ),
      ]..sort();
      expect(ids.map((id) => id.substring(9, 11)), ['01', '02', '03']);
    });

    test('generates unique IDs within the same second', () {
      final now = DateTime.utc(2026, 11, 16);
      final ids = {
        for (var i = 0; i < 200; i++)
          ItemIds.generate(now: now, deviceId: 'abc'),
      };
      expect(ids.length, greaterThan(195));
    });

    test('rejects unsafe or malformed IDs', () {
      expect(ItemIds.isValid('../../etc/passwd'), isFalse);
      expect(ItemIds.isValid('20261116T103512Z-a1b2c3'), isFalse);
      expect(ItemIds.isValid('20261116T103512Z-a1/b2-7f9e2d'), isFalse);
      expect(ItemIds.isValid(''), isFalse);
    });

    test('device IDs are 6 hex characters', () {
      expect(ItemIds.newDeviceId(), matches(RegExp(r'^[0-9a-f]{6}$')));
    });
  });
}
