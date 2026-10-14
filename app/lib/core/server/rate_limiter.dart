/// Sliding window rate limiter to mitigate brute-force attempts on PIN verification.
class RateLimiter {
  final int maxFails;
  final Duration window;
  final Map<String, List<DateTime>> _failures = {};

  RateLimiter({
    this.maxFails = 10,
    this.window = const Duration(minutes: 1),
  });

  bool isAllowed(String ip, [DateTime? now]) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(window);
    final list = _failures[ip];
    if (list == null) return true;

    // Filter entries older than the window
    list.removeWhere((timestamp) => timestamp.isBefore(cutoff));
    if (list.isEmpty) {
      _failures.remove(ip);
      return true;
    }
    return list.length < maxFails;
  }

  void recordFailure(String ip, [DateTime? now]) {
    final current = now ?? DateTime.now();
    _failures.putIfAbsent(ip, () => []).add(current);
  }

  void reset(String ip) {
    _failures.remove(ip);
  }

  void sweep([DateTime? now]) {
    final current = now ?? DateTime.now();
    final cutoff = current.subtract(window);
    _failures.removeWhere((_, list) {
      list.removeWhere((timestamp) => timestamp.isBefore(cutoff));
      return list.isEmpty;
    });
  }
}
