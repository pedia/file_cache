import 'package:test/test.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_cache/src/entry.dart';

void main() {
  test('read entry', () async {
    final e = CacheEntry(
      url: "http://a.com/?a=b",
      bytes: Uint8List.fromList([37, 42]),
      ctime: DateTime.parse('2012-02-27 13:27:00'),
      ttl: 3,
    );
    final f = File("foo");
    await e.writeTo(f);

    final g = await CacheEntry.fromFile(f);
    expectLater(g.url, e.url);
    expectLater(g.bytes, e.bytes);
    expectLater(g.ctime, e.ctime);
    expectLater(g.ttl, e.ttl);
  });
}
