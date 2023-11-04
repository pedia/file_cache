import 'package:flutter/material.dart';
import 'package:file_cache/file_cache_flutter.dart';

class FileCacheTestFrame extends StatefulWidget {
  createState() => _FileCacheTestFrameState();
}

class _FileCacheTestFrameState extends State<FileCacheTestFrame> {
  FileCache? fileCache;
  Map? map;

  @override
  initState() {
    super.initState();

    FileCacheFlutter.fromDefault().then((instance) {
      fileCache = instance;
    });
  }

  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // load
          ElevatedButton(
            onPressed: () {
              fileCache?.load('http://httpbin.org/cache/60').then((resp) {
                setState(() {});
              });
            },
            child: Text(""),
          ),

          // getJson
          ElevatedButton(
            onPressed: () {
              fileCache?.getJson(Uri.parse('http://httpbin.org/cache/600')).then((resp) {
                setState(() {
                  print(">> got $resp");
                  map = resp;
                });
              });
            },
            child:
                Text('map: ${map == null ? null : map!["result"][0]["name"]}'),
          ),

          Image(
              image: FileCacheImage(
            'http://httpbin.org/image/jpeg',
          )),

          //
          Text(fileCache == null ? '' : fileCache!.stats.toString())
        ],
      )),
    );
  }
}

void main() async {
  runApp(MaterialApp(home: FileCacheTestFrame()));
}
