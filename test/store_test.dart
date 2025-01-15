import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import '../lib/file_store.dart';

void main() {
  test('store', () async {
    final store = FileStore('cache3');

    final uri = Uri.parse('https://example.com/path');

    await store.write(
      http.Response.bytes(
        [1, 2, 99],
        200,
        headers: {'a': 'b'},
        request: http.Request('GET', uri),
      ),
    );

    final response = await store.read(uri);
    expect(response!.statusCode, 200);
    expect(response.headers['a'], 'b');
    expect(response.bodyBytes, [1, 2, 99]);
  });
}
