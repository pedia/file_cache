library file_cache;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_io/io.dart';
import 'package:http/http.dart' as http;

import 'file_store.dart';
import 'src/stats.dart';

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

class FileCache {
  FileCache({
    required String path,
    this.fetcher = defaultFetcher,
  }) {
    stats = CacheStats();
    _fileStore = FileStore(path);
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

    // local file cache
    var response = await _fileStore.read(uri);
    if (response != null) {
      stats.hitFiles += 1;
      stats.bytesRead += response.bodyBytes.length;
      completer.complete(response.bodyBytes);
      return completer.future;
    }

    response = await fetcher(uri);

    // TODO: cache 200, 204, 301, 302
    if (response.statusCode == HttpStatus.ok) {
      stats.bytesDownload += response.bodyBytes.length;

      await _fileStore.write(response);
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

  Future<http.Response?> load(Uri uri) => _fileStore.read(uri);

  Future<void> remove(Uri uri) => _fileStore.remove(uri);

  Future<void> clean() => _fileStore.clean();

  Future<void> scan() => _fileStore.scan();
}
