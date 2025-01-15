library file_cache;

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:path/path.dart';

class ScanResult {
  final int fileCount;
  final int bytes; // include headers
  final int expiredCount;
  ScanResult({
    required this.fileCount,
    required this.bytes,
    required this.expiredCount,
  });
}

class FileStore {
  final String path;
  FileStore(this.path);

  String url2path(Uri uri) {
    final int key = uri.hashCode;
    return join(path, '${key % 10}', '$key');
  }

  Future<void> write(http.Response response, {String? filePath}) async {
    filePath ??= url2path(response.request!.url);
    final file = File(filePath);

    await file.create(recursive: true);
    final writer = file.openWrite(encoding: utf8);

    // 200 https://example.com/path
    writer.writeln('${response.statusCode} ${response.request?.url}');

    // date: now
    final ctime = DateTime.now();
    writer.writeln('date: ${ctime}');

    // all headers
    for (final entry in response.headers.entries) {
      writer.writeln('${entry.key}: ${entry.value}');
    }
    writer.writeln(''); // end of headers

    // body
    writer.add(response.bodyBytes);
    await writer.close();
  }

  Future<http.Response?> read(Uri uri) async {
    final file = File(url2path(uri));
    if (!file.existsSync()) return null;

    final f = await file.open();
    // 200 https://example.com/path
    String line = await readUtil(f);
    var arr = line.split(' ');
    final statusCode = int.parse(arr[0]);
    // date: now
    await readUtil(f);

    // all headers
    final headers = <String, String>{};
    while (true) {
      line = await readUtil(f);
      if (line.isEmpty) {
        break;
      }

      arr = line.split(': ');
      headers[arr[0]] = arr[1];
    }

    // read all left
    final body = await f.read(f.lengthSync() - f.positionSync());
    return http.Response.bytes(body, statusCode, headers: headers);
  }

  /// Read [File] util char, 10 = '\n'
  Future<String> readUtil(RandomAccessFile file, {int charCode = 10}) async {
    var bytes = <int>[];
    while (true) {
      final int char = await file.readByte();
      if (char == -1) {
        throw StateError("eof pos:${file.positionSync()}");
      }

      if (char == charCode) break;

      bytes.add(char);
    }
    return String.fromCharCodes(bytes);
  }

  Future<void> remove(Uri uri) async {}
  Future<void> clean() async {}
  Future<ScanResult> scan() async {
    int fileCount = 0;
    int bytes = 0;
    int deleteCount = 0;
    final folder = Directory(path);
    if (folder.existsSync()) {
      await for (FileSystemEntity e in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        FileStat stat = await e.stat();
        if (stat.type == FileSystemEntityType.directory) continue;

        fileCount += 1;
        bytes += stat.size;

        // Entry? entry;
        // File file = File(e.path);
        // try {
        //   entry = await Entry.readFromFile(
        //     file,
        //     loadContent: false,
        //   );
        // } catch (error) {
        //   await file.delete(recursive: false);
        //   continue;
        // }
        // if (!entry.isValid()) {
        //   await e.delete(recursive: false);
        //   deleteCount += 1;
        // }
      }
    }
    return ScanResult(
      fileCount: fileCount,
      bytes: bytes,
      expiredCount: deleteCount,
    );
  }
}
