class CacheStats {
  CacheStats();

  /// Memory bytes of cached item used, not precised
  /// evicted item not traced.
  int bytesInMemory = 0;

  /// Count of miss in memory
  int missInMemory = 0;

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
    return "Bytes(Memory): $bytesInMemory\n"
        "Miss(Memory): $missInMemory\n"
        "Hit(Memory): $hitMemory\n"
        "Hit(Files): $hitFiles\n"
        "Bytes(File): $bytesInFile\n"
        "Bytes Read from File: $bytesRead\n"
        "Bytes download: $bytesDownload";
  }
}
