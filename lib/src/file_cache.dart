import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_io/io.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

import 'stats.dart';
import 'store.dart';
import 'header.dart';

final log = Logger('fcache');

/// [Fetcher] is function that produce http response for [url].
/// When cache not exists, [Fetcher] will be called.
///
/// The fetcher function should either return a value synchronously or a
/// [Future] which completes with the value asynchronously.
/// Use 'package:http/http.dart' instead 'dart:io'
typedef FutureOr<http.Response> Fetcher(Uri url);

Future<http.Response> defaultFetcher(Uri uri) {
  return http.Client().get(uri);
}

///
class FileCache {
  FileCache({
    required String path,
    this.fetcher = defaultFetcher,
  }) {
    stats = CacheStats();
    _fileStore = FileStore(path: path, stats: stats);
  }

  final Fetcher fetcher;

  late CacheStats stats;
  late FileStore _fileStore;

  Future<Uint8List> getBytes(
    Uri uri, {
    Encoding storeEncoding = utf8,
    int? forceCache,
  }) async {
    Completer<Uint8List> completer = Completer<Uint8List>();

    Entry? entry;

    final url = uri.toString();

    // 2 local file cache
    entry = await _fileStore.load(url);
    if (entry != null && entry.isValid()) {
      completer.complete(entry.bytes);
      return completer.future;
    }

    assert(!completer.isCompleted);

    final response = await fetcher(uri);

    // TODO: cache 200, 204, 301, 302
    if (response.statusCode != HttpStatus.ok)
      throw Exception(
          'HTTP request failed, status code: ${response.statusCode}, url: $url');

    if (response.bodyBytes.length == 0)
      throw Exception('cache file is empty: $url');

    stats.bytesDownload += response.bodyBytes.length;

    int ttl = forceCache ?? cacheableSeconds(response.headers);
    if (ttl != 0) {
      await _fileStore.store(
        Entry(
          url: url,
          bytes: response.bodyBytes,
          ttl: ttl,
          ctime: DateTime.now(),
        ),
        encoding: storeEncoding,
      );
    } else {
      log.warning("filecache: not cached $url");
    }
    completer.complete(response.bodyBytes);
    return completer.future;
  }

  Future<Map> getJson(Uri uri, {Encoding encoding = utf8}) async {
    return json.decode(await getString(uri, encoding: encoding));
  }

  Future<String> getString(Uri uri, {Encoding encoding = utf8}) async {
    return encoding.decode(await getBytes(uri, storeEncoding: encoding));
  }

  Future<Entry?> load(String url) => _fileStore.load(url);

  Future<void> remove(String url) => _fileStore.remove(url);

  Future<void> clean() => _fileStore.clean();

  Future<ScanResult> scan() => _fileStore.scan();

  /// Provider global instance
  static FileCache? _instance;
  static FileCache from(
      {Fetcher fetcher = defaultFetcher, required String path}) {
    if (_instance == null) {
      final fc = FileCache(path: path, fetcher: fetcher);

      _instance = fc;
    }
    return _instance!;
  }
}
