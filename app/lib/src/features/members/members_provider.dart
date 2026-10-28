import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberRow {
  final String tenantId;
  final String userId;
  final String role; // owner/manager/viewer
  final String status; // active/suspended
  final String? displayName;
  final String? email;
  MemberRow({
    required this.tenantId,
    required this.userId,
    required this.role,
    required this.status,
    this.displayName,
    this.email,
  });
}

/// Lists the members of the current tenant. Owner/manager only by RLS.
final membersProvider = FutureProvider<List<MemberRow>>((ref) async {
  final client = Supabase.instance.client;
  final members = await client
      .from('tenant_members')
      .select('tenant_id, user_id, role, status')
      .order('created_at') as List;
  // Fetch profiles for display names/emails.
  final ids = members.map((m) => m['user_id']).toList();
  Map<String, Map<String, dynamic>> profileMap = {};
  if (ids.isNotEmpty) {
    final profiles = await client
        .from('profiles')
        .select('id, display_name, email')
        .inFilter('id', ids) as List;
    for (final p in profiles) {
      profileMap[(p['id'] ?? '').toString()] = Map<String, dynamic>.from(p);
    }
  }
  return members.map((m) {
    final uid = (m['user_id'] ?? '').toString();
    final p = profileMap[uid];
    return MemberRow(
      tenantId: (m['tenant_id'] ?? '').toString(),
      userId: uid,
      role: (m['role'] ?? 'viewer').toString(),
      status: (m['status'] ?? 'active').toString(),
      displayName: p?['display_name']?.toString(),
      email: p?['email']?.toString(),
    );
  }).toList();
});

/// Lists the active tenants the current user belongs to (for the switcher).
final myTenantsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final rows = await client
      .from('tenant_members')
      .select('tenant_id, role, tenants(name)')
      .eq('status', 'active') as List;
  return rows.map((r) {
    final t = r['tenants'] as Map?;
    return {
      'tenant_id': (r['tenant_id'] ?? '').toString(),
      'role': (r['role'] ?? 'viewer').toString(),
      'name': (t?['name'] ?? 'Organisation').toString(),
    };
  }).toList();
});