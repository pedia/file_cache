import 'package:test/test.dart';

import '../lib/file_cache.dart';

void main() {
  test('getJson', () async {
    FileCache fileCache = await FileCache.fromDefault(path: "cache3");

    bool res = await fileCache.clean();
    expect(res, true);

    Map map = await fileCache.getJson('http://httpbin.org/cache/600?a=b');
    expect(map.length, 4);
    expect(map['args']['a'], 'b');
    expect(fileCache.stats.hitFiles, 0);
  });

  test('scan', () async {
    FileCache fileCache =
        await FileCache.fromDefault(path: "cache3", scan: true);

    Map map = await fileCache.getJson('http://httpbin.org/cache/600?a=b');
    expect(map.length, 4);
    expect(map['args']['a'], 'b');
    expect(fileCache.stats.hitFiles, 1);
  });
}
