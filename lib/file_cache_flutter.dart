library file_cache;

import 'package:file_cache/file_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui show instantiateImageCodec, ImmutableBuffer, Codec;

export 'package:file_cache/file_cache.dart';

class FileCacheFlutter extends FileCache {
  FileCacheFlutter({required String path, required Fetcher fetcher})
      : super(path: path, fetcher: fetcher);

  /// global instance, not thread safe
  static FileCacheFlutter? _instance;
  static fromDefault() async {
    if (_instance == null) {
      final dir = await getApplicationCacheDirectory();
      _instance = FileCacheFlutter(path: dir.path, fetcher: defaultFetcher);
    }
    return _instance!;
  }

  factory FileCacheFlutter.upgrade(FileCache fc) {
    return FileCacheFlutter(path: fc.store.path, fetcher: fc.fetcher);
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
  ImageStreamCompleter loadBuffer(FileCacheImage key,
      Future<ui.Codec> Function(ui.ImmutableBuffer buffer) decode) {
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
