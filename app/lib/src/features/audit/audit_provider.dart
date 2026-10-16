import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'audit_model.dart';

/// Latest 200 audit rows, newest first, optionally filtered by table.
/// Audit trail is append-only and never soft-deleted, so no `deleted_at`
/// filter here by design.
final auditProvider =
    FutureProvider.family<List<AuditRow>, String?>((ref, table) async {
  final client = Supabase.instance.client;
  final List res;
  if (table == null) {
    res = await client
        .from('audit_logs')
        .select('id, table_name, row_id, action, created_at')
        .order('created_at', ascending: false)
        .limit(200) as List;
  } else {
    res = await client
        .from('audit_logs')
        .select('id, table_name, row_id, action, created_at')
        .eq('table_name', table)
        .order('created_at', ascending: false)
        .limit(200) as List;
  }
  return res.map((r) => AuditRow.fromMap(r)).toList();
});

/// Distinct table names present in the audit trail (for filter chips).
final auditTablesProvider = FutureProvider<List<String>>((ref) async {
  final res = await Supabase.instance.client
      .from('audit_logs')
      .select('table_name')
      .order('table_name')
      .limit(1000);
  final seen = <String>{};
  for (final r in (res as List)) {
    seen.add((r['table_name'] ?? '').toString());
  }
  return seen.toList()..sort();
});
