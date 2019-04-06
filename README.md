# file_cache

File cached Json,Buffer,FileCacheImage for flutter package project.

Dart2 Ready

## Getting Started

```dart
import 'package:file_cache/file_cache.dart';

// Create the instance of FileCache
FileCache fileCache = await FileCache.fromDefault();

// Usage: get Json map
Map data = await fileCache.getJson('http://httpbin.org/cache/600');

// Usage: get bytes
Uint8List bytes = await fileCache.getBytes('http://httpbin.org/images/jpeg');

// Usage: replace NetworkImage
new Image(
    fit: BoxFit.cover,
    image: new FileCacheImage('http://httpbin.org/images/jpeg'),
);

// Usage: clean file cache
await fileCache.clean();

// Usage: statistics
print(fileCache.stats.toString());
// "Bytes(Memory): $bytesInMemory\n"
// "Miss(Memory): $missInMemory\n"
// "Hit(Memory): $hitMemory\n"
// "Hit(Files): $hitFiles\n"
// "Bytes(File): $bytesInFile\n"
// "Bytes Read from File: $bytesRead\n"
// "Bytes download: $bytesDownload";
```