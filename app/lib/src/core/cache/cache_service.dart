import 'package:hive_flutter/hive_flutter.dart';

/// Read-through JSON cache backed by Hive (IndexedDB on web).
///
/// ADR4: Hive is a *read* cache, never the source of truth. Postgres wins;
/// cache only serves when the network fails. Keys are per-provider query keys
/// (e.g. `loans:receivable`, `txns:200`). Values are raw PostgREST rows
/// (List of JSON maps) plus a saved-at timestamp.
///
/// Test seam: pass [path] to use a temp dir instead of initFlutter.
class CacheService {
  static const String boxName = 'nhisab_cache';
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> init({String? path}) async {
    if (_ready) return;
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }
    await Hive.openBox(boxName);
    _ready = true;
  }

  /// For tests: reset between cases.
  static Future<void> reset() async {
    if (!_ready) return;
    await Hive.box(boxName).clear();
  }

  static Box get _box => Hive.box(boxName);

  /// Fetch fresh rows, cache them, and return them. On network failure,
  /// return the last cached rows (possibly empty) with [fromCache]=true.
  static Future<({List rows, bool fromCache, DateTime? savedAt})>
      fetchOrCache({
    required String key,
    required Future<List> Function() fetch,
  }) async {
    try {
      final rows = await fetch();
      await writeRaw(key, rows);
      return (rows: rows, fromCache: false, savedAt: DateTime.now());
    } catch (_) {
      final cached = readRaw(key);
      if (cached != null) {
        return (rows: cached.rows, fromCache: true, savedAt: cached.savedAt);
      }
      rethrow;
    }
  }

  static Future<void> writeRaw(String key, List rows) async {
    if (!_ready) return;
    try {
      await _box.put(key, {
        'savedAt': DateTime.now().toIso8601String(),
        'rows': rows,
      });
    } catch (_) {
      // Cache write failures never break reads.
    }
  }

  static ({List rows, DateTime? savedAt})? readRaw(String key) {
    if (!_ready) return null;
    try {
      final v = _box.get(key);
      if (v is! Map) return null;
      final rows = v['rows'];
      if (rows is! List) return null;
      DateTime? savedAt;
      try {
        savedAt = DateTime.parse(v['savedAt'] as String);
      } catch (_) {}
      return (rows: rows, savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  /// Parse cached/raw rows into typed models, tolerating Hive's
  /// dynamic map shapes.
  static List<T> parseAll<T>(
      List rows, T Function(Map<String, dynamic> m) parse) {
    final out = <T>[];
    for (final r in rows) {
      if (r is Map) {
        try {
          out.add(parse(Map<String, dynamic>.from(r)));
        } catch (_) {
          // Skip corrupt rows, keep the rest.
        }
      }
    }
    return out;
  }

  /// Map payloads (for providers joining two queries, e.g. loans + pays).
  static Future<void> writeMap(String key, Map<String, dynamic> map) async {
    if (!_ready) return;
    try {
      await _box.put(key, {
        'savedAt': DateTime.now().toIso8601String(),
        'map': map,
      });
    } catch (_) {
      // Cache write failures never break reads.
    }
  }

  static Map<String, dynamic>? readMap(String key) {
    if (!_ready) return null;
    try {
      final v = _box.get(key);
      if (v is! Map) return null;
      final m = v['map'];
      if (m is! Map) return null;
      return Map<String, dynamic>.from(m);
    } catch (_) {
      return null;
    }
  }
}
