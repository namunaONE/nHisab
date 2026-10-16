import 'package:supabase_flutter/supabase_flutter.dart';

/// Fire-and-forget audit trail writer for `public.audit_logs`.
///
/// Never blocks UI and never throws: audit failures are swallowed so a logging
/// outage can't break money writes. Call after every insert/update/archive:
///
/// ```dart
/// final row = await client.from('parties').insert(data).select('id').single();
/// AuditLog.write(table: 'parties', rowId: row['id'] as String, action: 'insert', newData: data);
/// ```
class AuditLog {
  static Future<void> write({
    required String table,
    String? rowId,
    required String action, // 'insert' | 'update' | 'archive'
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  }) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      await client.from('audit_logs').insert({
        'table_name': table,
        'row_id': rowId,
        'action': action,
        'old_data': oldData,
        'new_data': _sanitize(newData),
        'actor': userId,
      });
    } catch (_) {
      // Swallowed by design — audit must never break money writes.
    }
  }

  /// Builds the audit payload without sending it (unit-testable).
  static Map<String, dynamic> payload({
    required String table,
    String? rowId,
    required String action,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    String? actor,
  }) {
    return {
      'table_name': table,
      'row_id': rowId,
      'action': action,
      'old_data': oldData,
      'new_data': _sanitize(newData),
      'actor': actor,
    };
  }

  /// Strips null values so jsonb stays compact. Never logs secrets — callers
  /// must not pass passwords, tokens, or full JWTs in data maps.
  static Map<String, dynamic>? _sanitize(Map<String, dynamic>? data) {
    if (data == null) return null;
    final out = <String, dynamic>{};
    for (final e in data.entries) {
      if (e.value == null) continue;
      final key = e.key.toLowerCase();
      if (key.contains('password') ||
          key.contains('secret') ||
          key.contains('token')) {
        continue;
      }
      out[e.key] = e.value;
    }
    return out;
  }
}
