import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'entry.dart';
import 'stats.dart';

/// A function that produces http response for [url],
/// for when a [Cache] needs to populate an entry.
///
/// The loader function should either return a value synchronously or a
/// [Future] which completes with the value asynchronously.
typedef FutureOr<HttpClientResponse> Loader(String url);

Future<HttpClientResponse> defaultLoader(String url) async {
  final Uri uri = Uri.parse(url);
  var httpClient = HttpClient();

  HttpClientRequest request = await httpClient.getUrl(uri);
  return await request.close();
}

class ScanResult {
  ScanResult({
    required this.fileCount,
    required this.bytes,
    required this.deleteCount,
  });

  final int fileCount;
  final int bytes;
  final int deleteCount;
}

class FileCache {
  FileCache({
    required this.path,
    this.loader = defaultLoader,
  });

  /// cache folder
  final String path;

  final CacheStats stats = CacheStats();

  /// Load (Http Response) if file not exists.
  final Loader loader;

  /// We can provider capabity for multi instance.
  /// This function ONLY for convenience
  static Future<FileCache> fromDefault({
    Loader loader = defaultLoader,
    String? path,
    bool scan = false,
  }) async {
    if (_instance == null) {
      final Completer<FileCache> completer = Completer<FileCache>();
      if (path == null) {
        Directory dir = await getTemporaryDirectory();
        path = "${dir.path}/cache2";
      }

      final fileCache = FileCache(
        path: path,
        loader: loader,
      );

      if (scan) {
        fileCache.scanFolder().then((ScanResult res) {
          print("FileCache in scan, delete ${res.deleteCount} file.");
          fileCache.stats.bytesInFile = res.bytes;
          completer.complete(fileCache);
        });
      } else {
        completer.complete(fileCache);
      }
      _instance = completer.future;
    }
    return _instance!;
  }

  static Future<FileCache>? _instance;

  Future<ScanResult> scanFolder() async {
    int fileCount = 0;
    int bytes = 0;
    int deleteCount = 0;

    Directory folder = Directory(path);
    if (folder.existsSync()) {
      await for (FileSystemEntity e in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        final stat = await e.stat();
        if (stat.type == FileSystemEntityType.directory) continue;

        fileCount += 1;
        bytes += stat.size;

        CacheEntry entry;
        File file = File(e.path);
        try {
          entry = await CacheEntry.fromFile(
            file,
            loadContent: false,
          );
        } catch (error) {
          await file.delete(recursive: false);
          continue;
        }
        if (!entry.isValid()) {
          await e.delete(recursive: false);
          deleteCount += 1;
        }
      }
    }
    return ScanResult(
      fileCount: fileCount,
      bytes: bytes,
      deleteCount: deleteCount,
    );
  }

  Future<bool> clean() async {
    Directory folder = Directory(path);
    if (folder.existsSync()) {
      await folder.delete(recursive: true);
      stats.bytesInFile = 0;
      return true;
    }
    return true;
  }

  /// Parse http header Cache-Control: max-age=300
  /// return 300 expire seconds
  int? cacheableSeconds(HttpClientResponse response) {
    String? val = response.headers.value(HttpHeaders.cacheControlHeader);
    if (val != null) {
      return extractSeconds(val);
    }
    return null;
  }

  int? extractSeconds(String val) {
    List<String> kv = val.split('=');
    if (kv.isNotEmpty) {
      int seconds = 0;
      try {
        seconds = int.parse(kv[1].trim());
      } catch (e) {}
      if (seconds > 0) return seconds;
    }
    return null;
  }

  Future<bool> remove(String url) async {
    final int key = url.hashCode;
    final File file = File("$path/${key % 10}/$key");
    await file.delete(recursive: false);
    return true;
  }

  Future<CacheEntry?> load(String url) async {
    final completer = Completer<CacheEntry?>();
    final key = url.hashCode;

    final file = File("$path/${key % 10}/$key");
    final exists = await file.exists();
    if (exists) {
      try {
        final entry = await CacheEntry.fromFile(file);
        stats.bytesRead += entry.length;
        stats.hitFiles += 1;
        completer.complete(entry);
      } catch (error) {
        // delete invalid files, it's not best
        await file.delete(recursive: false);
        completer.complete(null);
      }
    } else {
      completer.complete(null);
    }
    return completer.future;
  }

  //
  Future<void> store(
    String url,
    CacheEntry entry, {
    Encoding encoding = utf8,
  }) async {
    final int key = url.hashCode;

    File contentFile = File("$path/${key % 10}/$key");
    contentFile.create(recursive: true).then((_) {
      entry.writeTo(contentFile, encoding: encoding);

      stats.bytesInFile += entry.length;
    });
  }

  Future<Uint8List> getBytes(
    String url, {
    Encoding storeEncoding = utf8,
    int? forceCache,
  }) async {
    Completer<Uint8List> completer = Completer<Uint8List>();

    CacheEntry? entry;

    // local file cache
    entry = await load(url);
    if (entry != null && entry.isValid()) {
      completer.complete(entry.bytes);
      return completer.future;
    }

    assert(!completer.isCompleted);

    final HttpClientResponse? response = await loader(url);

    if (response == null || response.statusCode != HttpStatus.ok)
      throw Exception(
          'HTTP request failed, status code: ${response?.statusCode}, url: $url');

    final Uint8List bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.lengthInBytes == 0)
      throw Exception('NetworkImage is an empty file: $url');

    stats.bytesDownload += bytes.lengthInBytes;

    int? ttl = forceCache ?? cacheableSeconds(response);
    if (ttl != null) {
      await store(
        url,
        CacheEntry(
          url: url,
          bytes: bytes,
          ttl: ttl,
          ctime: DateTime.now(),
        ),
        encoding: storeEncoding,
      );
    } else {
      print("filecache: not cached $url");
    }
    completer.complete(bytes);

    return completer.future;
  }

  Future<String> getString(String url, {Encoding encoding = utf8}) async {
    Completer<String> completer = new Completer<String>();

    getBytes(url, storeEncoding: encoding).then((bytes) {
      completer.complete(encoding.decode(bytes));
    });

    return completer.future;
  }

  Future<Map> getJson(String url, {Encoding encoding = utf8}) async {
    return json.decode(await getString(url, encoding: encoding));
  }
}
