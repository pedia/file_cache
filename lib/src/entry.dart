import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final String url;
  final DateTime ctime;
  final int ttl;
  final Uint8List? bytes;

  const CacheEntry({
    required this.url,
    required this.bytes,
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

  /// create CacheEntry from [file]
  /// The file content like:
  /// url: xxxx
  /// length: xxxx
  /// ctime: xxx
  /// ttl: xxx
  /// content bytes...
  static Future<CacheEntry> fromFile(File file,
      {bool loadContent = true}) async {
    final Completer<CacheEntry> completer = Completer<CacheEntry>();

    RandomAccessFile rf = await file.open();
    // url
    String line = await readUtil(rf);
    String url = line.substring('url: '.length);

    line = await readUtil(rf);
    int length = int.parse(line.substring('length: '.length));

    // ctime
    line = await readUtil(rf);
    DateTime ctime = DateTime.parse(line.substring('ctime: '.length));

    // ttl
    line = await readUtil(rf);
    int ttl = int.parse(line.substring('ttl: '.length));

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
}
