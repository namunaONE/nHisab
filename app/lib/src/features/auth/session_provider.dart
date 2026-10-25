import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/cache_service.dart';
import '../../core/cache/outbox.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final sessionProvider = Provider<Session?>((ref) {
  return Supabase.instance.client.auth.currentSession;
});

/// Sign out and drop the per-user offline scopes.
///
/// The cache is keyed by user id and the outbox only replays entries belonging
/// to the signed-in user, so one account can never read or flush another
/// account's queued writes. The in-memory providers are invalidated by
/// [AuthGate] when the auth state changes.
Future<void> signOutAndClear() async {
  await Supabase.instance.client.auth.signOut();
  await CacheService.setUser(null);
  await Outbox.setUser(null);
}
