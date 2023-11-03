import 'package:universal_io/io.dart';

/// Parse http header, extract cache time
///
///   Cache-Control: max-age=300
///   Age: 100
///
/// More directives from [mdn](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)
/// All tests in test/header_test.dart
int cacheableSeconds(Map<String, String> headers) {
  // cache-control:
  final val = headers[HttpHeaders.cacheControlHeader];
  if (val != null) {
    final res = extractSeconds(val);
    if (res > 0) {
      // age:
      final age = headers[HttpHeaders.ageHeader];
      if (age != null) {
        try {
          return int.parse(age.trim());
        } catch (e) {}
      }
      return res;
    }
  }
  return 0;
}

int extractSeconds(String val) {
  List<String> kv = val.split('=');
  if (kv.length > 1) {
    String v = kv[1];
    final pos = v.indexOf(',');
    if (pos != -1) {
      v = v.substring(0, pos);
    }
    try {
      return int.parse(v.trim());
    } catch (e) {}
  }
  return 0;
}
