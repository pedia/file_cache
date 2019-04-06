import 'package:flutter/material.dart';
import 'package:file_cache/file_cache.dart';

class FileCacheTestFrame extends StatefulWidget {
  createState() => new _FileCacheTestFrameState();
}

class _FileCacheTestFrameState extends State<FileCacheTestFrame> {
  FileCache fileCache;
  Map map;
  CacheEntry entry;

  @override
  initState() {
    super.initState();

    FileCache.fromDefault().then((instance) {
      fileCache = instance;
    });
  }

  Widget build(BuildContext context) {
    return new Scaffold(
      body: new Center(
          child: new Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // load
          new RaisedButton(
            onPressed: () {
              fileCache ??
                  fileCache.load('http://httpbin.org/cache/60').then((resp) {
                    setState(() {
                      entry = resp;
                    });
                  });
            },
            child: new Text("entry ttl: ${entry == null ? null : entry.ttl}"),
          ),

          // getJson
          new RaisedButton(
            onPressed: () {
              fileCache.getJson('http://httpbin.org/cache/600').then((resp) {
                setState(() {
                  print(">> got $resp");
                  map = resp;
                });
              });
            },
            child: new Text(
                'map: ${map == null ? null : map["result"][0]["name"]}'),
          ),

          new Image(
              image: new FileCacheImage(
            'http://httpbin.org/image/jpeg',
          )),

          //
          new Text(fileCache == null ? '' : fileCache.stats.toString())
        ],
      )),
    );
  }
}

void main() async {
  FileCache fileCache = await FileCache.fromDefault();
  print(fileCache.path);
  runApp(new MaterialApp(home: new FileCacheTestFrame()));
}
