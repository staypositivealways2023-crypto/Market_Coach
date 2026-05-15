import 'dart:async';

/// Performance utilities for caching and optimization
class PerformanceUtils {
  /// Simple LRU cache for expensive computations
  static final _computationCache = LRUCache<String, dynamic>(maxSize: 50);

  /// Cache technical indicator calculations
  static T cacheComputation<T>(String key, T Function() computation) {
    if (_computationCache.containsKey(key)) {
      return _computationCache.get(key) as T;
    }

    final result = computation();
    _computationCache.put(key, result);
    return result;
  }

  /// Clear all caches
  static void clearCache() {
    _computationCache.clear();
  }

  /// Clear specific cache entry
  static void clearCacheEntry(String key) {
    _computationCache.remove(key);
  }
}

/// Simple LRU (Least Recently Used) Cache implementation
class LRUCache<K, V> {
  final int maxSize;
  final _cache = <K, V>{};

  LRUCache({required this.maxSize});

  bool containsKey(K key) => _cache.containsKey(key);

  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    // Move to end (most recently used)
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      // Remove least recently used (first item)
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = value;
  }

  void remove(K key) {
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
  }

  int get length => _cache.length;
}

/// Debouncer for search and expensive operations
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
