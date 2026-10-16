import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App user profile (separate from parties). One row per auth user.
class Profile {
  final String id;
  final String displayName;
  final String? email;
  final String? phone;
  final String role; // 'owner' | 'viewer'
  final String tenantId;
  final DateTime createdAt;

  Profile({
    required this.id,
    required this.displayName,
    this.email,
    this.phone,
    required this.role,
    required this.tenantId,
    required this.createdAt,
  });

  factory Profile.fromMap(Map<String, dynamic> r) {
    return Profile(
      id: (r['id'] ?? '') as String,
      displayName: (r['display_name'] ?? '') as String,
      email: r['email'] as String?,
      phone: r['phone'] as String?,
      role: (r['role'] ?? 'owner') as String,
      tenantId: (r['tenant_id'] ?? '') as String,
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }
}

/// Fetches the current user's profile from public.profiles.
/// Returns null when no profile exists yet (e.g. before trigger fires).
final profileProvider = FutureProvider<Profile?>((ref) async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return null;
  final res = await Supabase.instance.client
      .from('profiles')
      .select('id, display_name, email, phone, role, tenant_id, created_at')
      .eq('id', session.user.id)
      .maybeSingle();
  if (res == null) return null;
  return Profile.fromMap(res);
});

/// Whether the current user can perform write actions.
/// Viewers can only read.
final canWriteProvider = Provider<bool>((ref) {
  final async = ref.watch(profileProvider);
  return async.value?.role == 'owner' ? true : false;
});
