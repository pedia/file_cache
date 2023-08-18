import 'package:path_provider/path_provider.dart';
import 'package:quiver/cache.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

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

/// Stream util for ...
Future<String> readUtil(
  RandomAccessFile file, {
  int charCode = 10, // LF
}) async {
  var bytes = <int>[];
  while (true) {
    final int char = await file.readByte();
    if (char == -1) {
      throw StateError("eof");
    }

    if (char == charCode) break;

    bytes.add(char);
  }
  return String.fromCharCodes(bytes);
}

class CacheEntry {
  const CacheEntry({
    required this.url,
    required this.bytes,
    required this.ctime,
    required this.ttl,
  }) : assert(ttl > 0);

  final String url;
  final DateTime ctime;
  final int ttl;
  final Uint8List? bytes;
  // add mime type?

  int get length {
    return bytes == null ? 0 : bytes!.lengthInBytes;
  }

  bool isValid() {
    return ttl >= DateTime.now().difference(ctime).inSeconds;
  }

  /// create CacheEntry from [file]
  /// The file content like:
  /// url: xxxx
  /// length: xxxx
  /// ctime: xxx
  /// ttl: xxx
  /// content bytes...
  static Future<CacheEntry> fromFile(
    File file, {
    bool loadContent: true,
  }) async {
    final Completer<CacheEntry> completer = Completer<CacheEntry>();

    RandomAccessFile rf = await file.open();
    // url
    String line = await readUtil(rf);
    String url = line.split(':')[1];

    line = await readUtil(rf);
    int length = int.parse(line.split(':')[1]);

    // ctime
    line = await readUtil(rf);
    DateTime ctime = DateTime.parse(line.substring(7));

    // ttl
    line = await readUtil(rf);
    int ttl = int.parse(line.split(':')[1]);

    assert(length == rf.lengthSync() - rf.positionSync());

    // bytes
    Uint8List? bytes =
        loadContent ? await rf.read(rf.lengthSync() - rf.positionSync()) : null;
    await rf.close();

    completer.complete(CacheEntry(
      url: url,
      ctime: ctime,
      ttl: ttl,
      bytes: bytes,
    ));
    return completer.future;
  }

  Future writeTo(File file, {Encoding encoding: utf8}) async {
    final Completer<Null> completer = Completer<Null>();

    IOSink writer = file.openWrite(encoding: encoding);

    writer.writeln('url: $url');
    writer.writeln('length: $length');
    writer.writeln('ctime: ${ctime.toString()}');
    writer.writeln('ttl: $ttl');
    if (bytes != null) {
      writer.add(bytes!);
    }

    writer.close().then((_) {
      completer.complete();
    });

    return completer.future;
  }
}

class CacheStats {
  /// Not precised memory bytes of cached item used
  ///   evicted item not traced.
  int bytesInMemory = 0;

  /// Count of miss in memory, but hit file
  int missInMemory = 0;

  /// Bytes of total local file
  int bytesInFile = 0;

  /// Hit count of items in memory
  int hitMemory = 0;

  /// Hit count of items in files
  int hitFiles = 0;

  // Bytes read from file
  int bytesRead = 0;

  // Bytes download via http
  int bytesDownload = 0;

  @override
  String toString() {
    return "Bytes(Memory): $bytesInMemory\n"
        "Miss(Memory): $missInMemory\n"
        "Hit(Memory): $hitMemory\n"
        "Hit(Files): $hitFiles\n"
        "Bytes(File): $bytesInFile\n"
        "Bytes Read from File: $bytesRead\n"
        "Bytes download: $bytesDownload";
  }
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
    this.useMemory: false,
    this.loader = defaultLoader,
  });

  /// cache folder
  final String path;

  /// keep bytes in memory, default false
  final bool useMemory;

  final Cache _cache = MapCache<String, CacheEntry>.lru(maximumSize: 300);
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

      final FileCache fileCache = FileCache(
        path: path,
        useMemory: false,
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
        FileStat stat = await e.stat();
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
    final Completer<CacheEntry?> completer = Completer<CacheEntry?>();
    final int key = url.hashCode;

    final File file = File("$path/${key % 10}/$key");
    bool exists = await file.exists();
    if (exists) {
      CacheEntry entry;
      try {
        entry = await CacheEntry.fromFile(file);
        stats.bytesRead += entry.length;
        stats.hitFiles += 1;
        completer.complete(entry);
      } catch (error) {
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
    Encoding encoding: utf8,
  }) async {
    final int key = url.hashCode;

    if (useMemory) {
      _cache.set(url, entry).then((_) {
        stats.bytesInMemory += entry.length;
      });
    }

    File contentFile = File("$path/${key % 10}/$key");
    contentFile.create(recursive: true).then((_) {
      entry.writeTo(contentFile, encoding: encoding);

      stats.bytesInFile += entry.length;
    });
  }

  Future<Uint8List> getBytes(
    String url, {
    Encoding storeEncoding: utf8,
    int? forceCache,
  }) async {
    Completer<Uint8List> completer = Completer<Uint8List>();

    CacheEntry? entry;

    // 1 memory cache first
    if (useMemory) {
      entry = await _cache.get(url);
      if (entry != null && entry.isValid()) {
        stats.hitMemory += 1;
        completer.complete(entry.bytes);
        return completer.future;
      }
    }

    // 2 local file cache
    entry = await load(url);
    if (entry != null && entry.isValid()) {
      if (useMemory) {
        stats.missInMemory += 1;
        _cache.set(url, entry).then((_) {
          stats.bytesInMemory += entry!.length;
        });
      }

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
