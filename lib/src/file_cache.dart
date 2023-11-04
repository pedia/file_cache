import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_io/io.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

import 'stats.dart';
import 'store.dart';
import 'header.dart';

var log = Logger('file_cache');

Future<http.Response> defaultLoader(Uri uri) async {
  var client = http.Client();

  return await client.get(uri);
}

/// A function that produces http response for [url],
/// for when a [Cache] needs to populate an entry.
///
/// The loader function should either return a value synchronously or a
/// [Future] which completes with the value asynchronously.
/// Use 'package:http/http.dart' instead 'dart:io'
typedef FutureOr<http.Response> Loader(Uri url);

class FileCache {
  static Completer<FileCache>? _completer;

  late CacheStats stats; // = CacheStats();
  late MemoryStore? _memoryStore;
  late FileStore _fileStore;

  /// Load (Http Response) if file not exists.
  final Loader loader;

  FileCache({
    required String path,
    bool useMemory = false,
    this.loader = defaultLoader,
  }) {
    stats = CacheStats();
    _memoryStore = useMemory ? MemoryStore() : null;
    _fileStore = FileStore(path: path, stats: stats);
  }

  Future<Uint8List> getBytes(
    Uri uri, {
    Encoding storeEncoding = utf8,
    int? forceCache,
  }) async {
    Completer<Uint8List> completer = Completer<Uint8List>();

    Entry? entry;

    final url = uri.toString();

    // 1 memory cache first
    if (_memoryStore != null) {
      entry = await _memoryStore?.load(url);
      if (entry != null && entry.isValid()) {
        stats.hitMemory += 1;
        completer.complete(entry.bytes);
        return completer.future;
      }
    }

    // 2 local file cache
    entry = await _fileStore.load(url);
    if (entry != null && entry.isValid()) {
      if (_memoryStore != null) {
        stats.missInMemory += 1;
        _memoryStore?.store(entry).then((_) {
          stats.bytesInMemory += entry!.length;
        });
      }

      completer.complete(entry.bytes);
      return completer.future;
    }

    assert(!completer.isCompleted);

    final response = await loader(uri);

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

  /// Provider global instance
  static Future<FileCache> from({
    Loader loader = defaultLoader,
    required String path,
    bool scan = false,
  }) async {
    if (_completer == null) {
      final completer = Completer<FileCache>();
      final fileCache = FileCache(
        path: path,
        useMemory: false,
        loader: loader,
      );

      if (scan) {
        fileCache._fileStore.scan();
      }
      completer.complete(fileCache);
      _completer = completer;
    }
    return _completer!.future;
  }
}
