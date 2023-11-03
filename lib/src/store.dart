import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:quiver/cache.dart';
import 'package:universal_io/io.dart';
import 'stats.dart';

/// Read [Stream] util char, 10 = '\n'
Future<String> readUtil(RandomAccessFile file, {int charCode = 10}) async {
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

/// Store Http response to a file, like:
/// url: xxxx
/// length: xxxx
/// ctime: xxx
/// ttl: xxx
/// content bytes...
///
/// Load or store via [Entry]
class Entry {
  final String url;
  final DateTime ctime;
  final int ttl;
  final Uint8List? bytes;
  const Entry({
    required this.url,
    this.bytes,
    required this.ctime,
    required this.ttl,
  }) : assert(ttl > 0);
  // add mime type?

  int get length {
    return bytes == null ? 0 : bytes!.lengthInBytes;
  }

  bool isValid() {
    return ttl >= DateTime.now().difference(ctime).inSeconds;
  }

  Future<void> writeTo(File file, {Encoding encoding = utf8}) async {
    final completer = Completer<void>();

    final writer = file.openWrite(encoding: encoding);

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

  /// load `Entry` from [file]
  static Future<Entry> readFromFile(File file,
      {bool loadContent = true}) async {
    final rf = await file.open();
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
    final bytes =
        loadContent ? await rf.read(rf.lengthSync() - rf.positionSync()) : null;
    await rf.close();

    return Entry(
      url: url,
      ctime: ctime,
      ttl: ttl,
      bytes: bytes,
    );
  }
}

class ScanResult {
  final int fileCount;

  final int bytes;
  final int deleteCount;
  ScanResult({
    required this.fileCount,
    required this.bytes,
    required this.deleteCount,
  });
}

class FileStore {
  FileStore({required this.path, required this.stats});

  /// cache folder
  final String path;
  final CacheStats stats;

  // Scan path
  Future<ScanResult> scan() async {
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

        Entry? entry;
        File file = File(e.path);
        try {
          entry = await Entry.readFromFile(
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

  Future<void> clean() async {
    Directory folder = Directory(path);
    if (folder.existsSync()) {
      await folder.delete(recursive: true);
      // stats.bytesInFile = 0;
    }
  }

  Future<Entry?> load(String url) async {
    final completer = Completer<Entry?>();
    final int key = url.hashCode;

    final File file = File("$path/${key % 10}/$key");
    bool exists = await file.exists();
    if (exists) {
      Entry? entry;
      try {
        entry = await Entry.readFromFile(file);
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

  Future<void> remove(String url) async {
    final int key = url.hashCode;
    await File("$path/${key % 10}/$key").delete(recursive: false);
  }

  //
  Future<void> store(Entry entry, {Encoding encoding = utf8}) {
    final completer = Completer<void>();
    final int key = entry.url.hashCode;

    final contentFile = File("$path/${key % 10}/$key");
    contentFile.create(recursive: true).then((_) {
      entry.writeTo(contentFile, encoding: encoding);

      // stats.bytesInFile += entry.length;
      completer.complete();
    });
    return completer.future;
  }
}

class MemoryStore {
  MemoryStore({int maximumSize = 1000})
      : _cache = MapCache<String, Entry>.lru(maximumSize: maximumSize);

  final MapCache<String, Entry> _cache;

  Future<Entry?> load(String url) => _cache.get(url);

  Future<void> store(Entry entry, {Encoding encoding = utf8}) =>
      _cache.set(entry.url, entry);

  Future<void> remove(String url) => _cache.invalidate(url);

  Future<void> clean() async {}
}
