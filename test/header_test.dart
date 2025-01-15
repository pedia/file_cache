import 'package:test/test.dart';
import 'package:tuple/tuple.dart';

import '../lib/src/header.dart';

void main() {
  final headers = [
    Tuple2({'cache-control': 's-maxage=604800'}, 604800),
    Tuple2({'cache-control': 'max-age=604800'}, 604800),
    Tuple2({'cache-control': 'max-age=0'}, 0),
    Tuple2({'cache-control': 'max-stale=3600'}, 3600),
    Tuple2({'cache-control': 'min-fresh=600', 'age': '100'}, 100),
    Tuple2({'cache-control': 'max-age=604800, must-revalidate'}, 604800),
    Tuple2({'cache-control': 'public, max-age=604800'}, 604800),
    Tuple2({'cache-control': 'public, max-age=604800, immutable'}, 604800),
    Tuple2({'cache-control': 'max-age=604800, stale-while-revalidate=86400'},
        604800),
    Tuple2({'cache-control': 'max-age=604800, stale-if-error=86400'}, 604800),
    Tuple2({'cache-control': 'no-cache'}, 0),
    Tuple2({'cache-control': 'no-store'}, 0),
    Tuple2({'cache-control': 'private'}, 0),
    Tuple2({'cache-control': 'must-understand, no-store'}, 0),
    Tuple2({'cache-control': 'public'}, 0),
  ];

  test('cacheableSeconds', () {
    headers.forEach((t) {
      final s = cacheableSeconds(t.item1);
      expect(s, t.item2, reason: '${t.item1}');
    });
  });

  test('ExpiredSecondsParse', () {
    final vs = {
      's-maxage=604800': 604800,
      'max-age=604800': 604800,
      'max-age=0': 0,
      'max-age=300': 300,
      'max-stale=3600': 3600,
      'min-fresh=600': 600,
      'max-age=604800, must-revalidate': 604800,
      'public, max-age=604800': 604800,
      'public, max-age=604800, immutable': 604800,
      'max-age=604800, stale-while-revalidate=86400': 604800,
      'max-age=604800, stale-if-error=86400': 604800,
      'max-age=604800, private': 604800,
    };
    vs.forEach((k, v) {
      expect(extractSeconds(k), v, reason: k);
    });
  });
}
