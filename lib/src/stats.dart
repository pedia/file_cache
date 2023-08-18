class CacheStats {
  /// Bytes of total local file
  int bytesInFile = 0;

  /// Hit count of items in memory
  int hitMemory = 0;

  /// Hit count of items in files
  int hitFiles = 0;

  // Bytes read from file
  int bytesRead = 0;

  // Bytes download via http
  int bytesDownload = 0;

  @override
  String toString() {
    return "Hit(Files): $hitFiles\n"
        "Bytes(File): $bytesInFile\n"
        "Bytes Read from File: $bytesRead\n"
        "Bytes download: $bytesDownload";
  }
}
