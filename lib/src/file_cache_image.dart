import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui show instantiateImageCodec, Codec;
import 'package:path_provider/path_provider.dart';
import 'package:universal_io/io.dart';
import 'package:path/path.dart' as p;

import 'file_cache.dart';

class FileCacheFlutter {
  static Future<FileCache> fromDefault({
    Fetcher fetcher = defaultFetcher,
    String? path,
  }) async {
    if (path == null) {
      Directory dir = await getTemporaryDirectory();
      path = p.join(dir.path, 'cache2');
    }
    return FileCache.from(path: path, fetcher: fetcher);
  }
}

class FileCacheImage extends ImageProvider<FileCacheImage> {
  /// Creates an ImageProvider which loads an image from the [url], using the [scale].
  const FileCacheImage(this.url, {this.scale = 1.0});

  /// The URL from which the image will be fetched.
  final String url;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  @override
  Future<FileCacheImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<FileCacheImage>(this);
  }

  @override
  ImageStreamCompleter load(FileCacheImage key, DecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key),
      scale: key.scale,
    );
  }

  Future<ui.Codec> _loadAsync(FileCacheImage key) async {
    assert(key == this);
    FileCache fileCache = await FileCacheFlutter.fromDefault();

    final Uint8List bytes = await fileCache.getBytes(Uri.parse(key.url));
    return await ui.instantiateImageCodec(bytes);
  }
}
