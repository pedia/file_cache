import 'package:path_provider/path_provider.dart';
import 'package:quiver/cache.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'consolidate_response.dart';

/// A function that produces http response for [url],
/// for when a [Cache] needs to populate an entry.
///
/// The loader function should either return a value synchronously or a
/// [Future] which completes with the value asynchronously.
typedef FutureOr<HttpClientResponse> Loader(String url);

/// Stream util read some String unit [charCode]
Future<String> readUtil(
  RandomAccessFile file, {
  int charCode: 10, // LF
}) async {
  var bytes = <int>[];
  while (true) {
    final int char = await file.readByte();
    if (char == charCode) break;

    bytes.add(char);
  }
  return new String.fromCharCodes(bytes);
}

class CacheEntry {
  const CacheEntry({
    this.url,
    this.bytes,
    this.ctime,
    this.ttl,
  });

  final String url;
  final DateTime ctime;
  final int ttl;
  final Uint8List bytes;
  // mime type, maybe not necessary

  int get length {
    return bytes != null ? bytes.lengthInBytes : 0;
  }

  bool isValid() {
    return ttl >= new DateTime.now().difference(ctime).inSeconds;
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
    final Completer<CacheEntry> completer = new Completer<CacheEntry>();

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
    Uint8List bytes =
        loadContent ? await rf.read(rf.lengthSync() - rf.positionSync()) : null;
    await rf.close();

    var entry = new CacheEntry(
      url: url,
      ctime: ctime,
      ttl: ttl,
      bytes: bytes,
    );

    completer.complete(entry);
    return completer.future;
  }

  Future<Null> writeTo(File file, {Encoding encoding: utf8}) async {
    final Completer<Null> completer = new Completer<Null>();

    IOSink writer = file.openWrite(encoding: encoding);

    await writer.writeln('url: $url');
    await writer.writeln('length: $length');
    await writer.writeln('ctime: ${ctime.toString()}');
    await writer.writeln('ttl: $ttl');
    await writer.add(bytes);
    await writer.close();

    completer.complete(null);
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
  /// TODO: Initialize this in startup
  int bytesInFile = 0;

  /// Hit count of items in memory
  int hitMemory = 0;

  // Bytes read from file
  int bytesRead = 0;

  // Bytes download via http
  int bytesDownload = 0;

  @override
  String toString() {
    return "Bytes(Memory): $bytesInMemory\n"
        "Miss(Memory): $missInMemory\n"
        "Hit(Memory): $hitMemory\n"
        "Bytes(File): $bytesInFile\n"
        "Bytes Read from File: $bytesRead\n"
        "Bytes download: $bytesDownload";
  }
}

class ScanResult {
  ScanResult({
    this.fileCount,
    this.bytes,
    this.deleteCount,
  });

  final int fileCount;
  final int bytes;
  final int deleteCount;
}

class FileCache {
  FileCache._({
    this.path,
    this.useMemory: false,
    this.loader,
  });

  final String path;

  final bool useMemory;

  final Cache _cache = new MapCache<String, CacheEntry>.lru(maximumSize: 300);
  final CacheStats stats = new CacheStats();

  /// Load (Http Response) if file not exists.
  final Loader loader;

  /// We can provider capabity for multi instance.
  /// This function ONLY for convenience
  static Future<FileCache> fromDefault({
    Loader loader,
  }) async {
    if (_instance == null) {
      Directory dir = await getTemporaryDirectory();

      _instance = new FileCache._(
        path: "${dir.path}/cache2",
        useMemory: false,
        loader: loader,
      );

      _instance.scanFolder().then((ScanResult res) {
        // TODO: log print("FileCache in scan, delete ${res.deleteCount} file.");
        _instance.stats.bytesInFile = res.bytes;
      });
    }
    return _instance;
  }

  static FileCache _instance;

  Future<ScanResult> scanFolder() async {
    int fileCount = 0;
    int bytes = 0;
    int deleteCount = 0;
    Directory folder = new Directory(path);
    if (folder.existsSync()) {
      await for (FileSystemEntity e in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        FileStat stat = await e.stat();
        if (stat.type == FileSystemEntityType.DIRECTORY) continue;

        fileCount += 1;
        bytes += stat.size;

        CacheEntry entry;
        File file = new File(e.path);
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
    return new ScanResult(
      fileCount: fileCount,
      bytes: bytes,
      deleteCount: deleteCount,
    );
  }

  Future<bool> clean() async {
    Directory folder = new Directory(path);
    if (folder.existsSync()) {
      await folder.delete(recursive: true);
      stats.bytesInFile = 0;
      return true;
    }
    return false;
  }

  /// Parse http header Cache-Control: max-age=300
  /// return 300 expire seconds
  int cacheableSeconds(HttpClientResponse response) {
    String head = response.headers.value(HttpHeaders.CACHE_CONTROL);
    if (head != null) {
      List<String> kv = head.split('=');
      if (kv.isNotEmpty) {
        int seconds = int.parse(kv[1]);
        if (seconds > 0) return seconds;
      }
    }
    return null;
  }

  Future<CacheEntry> load(String url) async {
    assert(url is String);

    final Completer<CacheEntry> completer = new Completer<CacheEntry>();
    final int key = url.hashCode;

    final File file = new File("$path/${key % 10}/$key");
    bool exists = await file.exists();
    if (exists) {
      CacheEntry entry;
      try {
        entry = await CacheEntry.fromFile(file);
        stats.bytesRead += entry.length;
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

  /// Store to cache folder
  void store(String url, CacheEntry entry, {Encoding encoding: utf8}) async {
    final int key = url.hashCode;

    if (useMemory) {
      _cache.set(url, entry).then((_) {
        stats.bytesInMemory += entry.length;
      });
    }

    File contentFile = new File("$path/${key % 10}/$key");
    contentFile.create(recursive: true).then((_) {
      entry.writeTo(contentFile, encoding: encoding);

      stats.bytesInFile += entry.length;
    });
  }

  Future<Uint8List> getBytes(String url, {Encoding storeEncoding: utf8}) async {
    Completer<Uint8List> completer = new Completer<Uint8List>();

    CacheEntry entry;

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
          stats.bytesInMemory += entry.length;
        });
      }

      completer.complete(entry.bytes);
      return completer.future;
    }

    assert(!completer.isCompleted);

    if (loader == null) {
      completer.complete(null);
      return completer.future;
    }

    final HttpClientResponse response = await loader(url);

    if (response.statusCode != HttpStatus.OK)
      throw new Exception(
          'HTTP request failed, statusCode: ${response?.statusCode}, $url');

    final Uint8List bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.lengthInBytes == 0)
      throw new Exception('NetworkImage is an empty file: $url');

    stats.bytesDownload += bytes.lengthInBytes;

    completer.complete(bytes);

    int ttl = cacheableSeconds(response);
    if (ttl != null) {
      store(
        url,
        new CacheEntry(
          url: url,
          bytes: bytes,
          ttl: ttl,
          ctime: new DateTime.now(),
        ),
        encoding: storeEncoding,
      );
    }

    return completer.future;
  }

  Future<Map> getJson(String url, {Encoding encoding: utf8}) async {
    Completer<Map> completer = new Completer<Map>();

    Uint8List bytes = await getBytes(url, storeEncoding: encoding);

    String str = encoding.decode(bytes);
    completer.complete(json.decode(str));

    return completer.future;
  }
}
