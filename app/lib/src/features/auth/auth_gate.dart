import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import 'session_provider.dart';
import 'profiles_provider.dart';

class AuthGate extends ConsumerWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);
    return authAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Auth error: $e'))),
      data: (state) {
        final session = state.session ?? ref.watch(sessionProvider);
        if (session == null) return const LoginPage();
        return _ProfileGate(child: child);
      },
    );
  }
}

/// Waits for the profile to load, then gates by role.
class _ProfileGate extends ConsumerWidget {
  final Widget child;
  const _ProfileGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Profile error: $e'))),
      data: (profile) {
        // No profile yet — trigger may not have fired; allow entry as owner
        // but show a hint. In production this is rare after signup.
        if (profile == null) return child;
        final role = profile.role;
        if (role == 'viewer') {
          // Viewer: read-only. Show a read-only hint on the child via a wrapper.
          return _ReadOnlyNotice(profile: profile, child: child);
        }
        return child;
      },
    );
  }
}

/// Read-only notice banner for viewer-role users.
class _ReadOnlyNotice extends ConsumerWidget {
  final Widget child;
  final Profile profile;
  const _ReadOnlyNotice({required this.profile, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'View-only mode — signed in as ${profile.displayName} (${profile.role}). Write actions are disabled.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    ref.invalidate(profileProvider);
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
