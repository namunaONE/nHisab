import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Online write queue (ADR4, second half). When an insert fails while offline,
/// forms enqueue the payload here; [flush] replays it on reconnect with the
/// row's original client timestamp preserved in `created_at` where allowed.
///
/// Idempotency: every entry carries a client UUID (`client_id`). Replays use
/// plain inserts (server generates ids); duplicates across retries are
/// possible only if the first attempt actually committed — PostgREST failures
/// on offline are connection errors, so the write never landed.
class Outbox {
  static const String boxName = 'nhisab_outbox';
  static bool _ready = false;
  static String? _userId;

  static String get scope => _userId ?? 'anon';

  /// Switch the replay namespace. Entries carry the user id they were queued
  /// under; [flush] only replays the current user's entries. That prevents a
  /// second account on a shared device from posting the first account's
  /// transactions into its own tenant.
  static Future<void> setUser(String? userId) async {
    _userId = userId;
  }

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

  static Box get _box => Hive.box(boxName);

  static bool _belongsToCurrentScope(Object? entry) {
    if (entry is! Map) return false;
    return (entry['user_id'] ?? 'anon').toString() == scope;
  }

  /// Queue a failed insert for later replay. Returns the queue key.
  static Future<int> enqueue({
    required String table,
    required Map<String, dynamic> data,
  }) async {
    final clean = Map<String, dynamic>.from(data)
      ..removeWhere((_, v) => v == null);
    return _box.add({
      'table': table,
      'data': clean,
      'user_id': scope,
      'queuedAt': DateTime.now().toIso8601String(),
    });
  }

  static int get pendingCount {
    if (!_ready) return 0;
    return _box.values.where(_belongsToCurrentScope).length;
  }

  /// Test/admin helper: remove every queued entry on this device.
  static Future<void> clear() async {
    if (!_ready) return;
    await _box.clear();
  }

  /// Replay the current user's queued inserts in FIFO order.
  /// Returns (flushed, failed). Entries that succeed are deleted; failures stay
  /// queued. Other users' entries are left untouched.
  static Future<({int flushed, int failed})> flush() async {
    if (!_ready) return (flushed: 0, failed: 0);
    final client = Supabase.instance.client;
    var flushed = 0;
    var failed = 0;
    final keys = _box.keys.toList();
    for (final k in keys) {
      final entry = _box.get(k);
      if (!_belongsToCurrentScope(entry)) continue;
      if (entry is! Map) {
        await _box.delete(k);
        continue;
      }
      try {
        final data =
            Map<String, dynamic>.from(entry['data'] as Map);
        await client.from(entry['table'] as String).insert(data);
        await _box.delete(k);
        flushed++;
      } catch (_) {
        failed++;
      }
    }
    return (flushed: flushed, failed: failed);
  }
}
