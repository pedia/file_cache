import 'package:test/test.dart';

import 'package:file_cache/file_cache.dart';

void main() {
  test('getJson', () async {
    FileCache fileCache = await FileCache.fromDefault();
    expect(await fileCache.getJson('foo'), null);
  });
}
