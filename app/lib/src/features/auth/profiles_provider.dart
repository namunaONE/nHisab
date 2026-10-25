import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_provider.dart';

/// App user profile (separate from parties). One row per auth user.
class Profile {
  final String id;
  final String displayName;
  final String? email;
  final String? phone;

  /// 'owner' | 'manager' | 'viewer'. Unknown values fail closed.
  final String role;
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
      // Fail closed: a missing/unknown role must not become owner.
      role: (r['role'] ?? 'unknown') as String,
      tenantId: (r['tenant_id'] ?? '') as String,
      createdAt: DateTime.tryParse((r['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get isWriter => role == 'owner' || role == 'manager';
}

/// The authenticated user id, kept in sync with Supabase auth events.
///
/// [profileProvider] must be keyed by this value; otherwise a profile cached
/// for one user could be reused after a fast sign-out/sign-in on a shared
/// device.
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider).valueOrNull;
  return auth?.session?.user.id ??
      Supabase.instance.client.auth.currentUser?.id;
});

/// Fetches the current user's profile from public.profiles.
/// Returns null when no profile exists yet (e.g. before invite acceptance).
final profileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final res = await Supabase.instance.client
      .from('profiles')
      .select('id, display_name, email, phone, role, tenant_id, created_at')
      .eq('id', userId)
      .maybeSingle();
  if (res == null) return null;
  return Profile.fromMap(res);
});

/// Whether the current user can perform write actions.
/// Viewers can only read; unknown profiles fail closed.
final canWriteProvider = Provider<bool>((ref) {
  final async = ref.watch(profileProvider);
  return async.value?.isWriter == true;
});
