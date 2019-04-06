# file_cache

File cached Json,Buffer,FileCacheImage for flutter package project.

<font color="green">Dart2 Ready</font>

## Getting Started

```dart
import 'package:file_cache/file_cache.dart';

// Provider a Loader function for Http request;
Future<HttpClientResponse> loader(String url) async {
  final Uri uri = Uri.parse(url);

  HttpClientRequest request = await httpClient.getUrl(uri);
  return await request.close();
}

// Create the instance of FileCache
FileCache fileCache = await FileCache.fromDefault(
  httpClient: httpClient,
  loader: loader,
);

// Usage: get Json map
Map data = await fileCache.getJson(url);

// Usage: get bytes
Uint8List bytes = await fileCache.getBytes(url);

// Usage: replace NetworkImage
new Image(
    fit: BoxFit.cover,
    image: new FileCacheImage(url),
);

// Usage: clean file cache
await fileCache.clean();

// Usage: statistics
print(fileCache.stats.toString());
// "Bytes(Memory): $bytesInMemory\n"
// "Miss(Memory): $missInMemory\n"
// "Hit(Memory): $hitMemory\n"
// "Bytes(File): $bytesInFile\n"
// "Bytes Read from File: $bytesRead\n"
// "Bytes download: $bytesDownload";
```