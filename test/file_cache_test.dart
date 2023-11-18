import 'package:test/test.dart';

import 'package:file_cache/file_cache.dart';

void main() {
  test('getJson', () async {
    final fileCache = FileCache.from(path: "cache3");

    await fileCache.clean();

    Map map =
        await fileCache.getJson(Uri.parse('https://httpbin.org/cache/600?a=b'));
    expect(map.length, 4);
    expect(map['args']['a'], 'b');
    expect(fileCache.stats.hitFiles, 0);
  });

  test('scan', () async {
    final fileCache = FileCache.from(path: "cache3");

    Map map =
        await fileCache.getJson(Uri.parse('https://httpbin.org/cache/600?a=b'));
    expect(map.length, 4);
    expect(map['args']['a'], 'b');
    expect(fileCache.stats.hitFiles, 1);
  });
}
