import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/cache_service.dart';
import '../../core/cache/outbox.dart';
import '../accounts/accounts_provider.dart';
import '../audit/audit_provider.dart';
import '../budgets/budgets_provider.dart';
import '../categories/categories_provider.dart';
import '../loans/loans_provider.dart';
import '../notifications/notifications_provider.dart';
import '../parties/parties_provider.dart';
import '../payments/payments_provider.dart';
import '../transactions/transactions_provider.dart';
import 'login_page.dart';
import 'profiles_provider.dart';
import 'session_provider.dart';

class AuthGate extends ConsumerWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  /// Re-key the offline stores and drop every in-memory read on account
  /// change. Providers are not auto-disposed, so without this a fast
  /// sign-out/sign-in on a shared browser could reuse the previous user's
  /// loaded rows.
  static void _onUserChanged(WidgetRef ref, String? userId) {
    unawaited(CacheService.setUser(userId));
    unawaited(Outbox.setUser(userId));
    ref.invalidate(profileProvider);
    ref.invalidate(loansProvider);
    ref.invalidate(partiesProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(budgetsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(auditProvider);
    ref.invalidate(auditTablesProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AuthState>>(authStateProvider, (prev, next) {
      final previousId = prev?.valueOrNull?.session?.user.id;
      final nextId = next.valueOrNull?.session?.user.id;
      if (previousId == nextId) return;
      _onUserChanged(ref, nextId);
    });

    final authAsync = ref.watch(authStateProvider);
    return authAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _BlockedScreen(
        title: 'Sign-in error',
        message: e.toString(),
        onRetry: () => ref.invalidate(authStateProvider),
      ),
      data: (state) {
        final session = state.session ?? ref.watch(sessionProvider);
        if (session == null) return const LoginPage();
        return _ProfileGate(child: child);
      },
    );
  }
}

/// Waits for the profile to load, then gates by role.
///
/// Fail closed: an authenticated user without a profile/membership must not
/// reach the app. The previous version returned [child] when the profile was
/// null, which made a missing trigger or a deleted profile an authorization
/// bypass.
class _ProfileGate extends ConsumerWidget {
  final Widget child;
  const _ProfileGate({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _BlockedScreen(
        title: 'Account check failed',
        message:
            'We could not verify your account. Check your connection and try again.',
        details: e.toString(),
        onRetry: () => ref.invalidate(profileProvider),
      ),
      data: (profile) {
        if (profile == null) {
          return _BlockedScreen(
            title: 'Account not provisioned',
            message:
                'This account has not been invited to an nHisab organisation. Ask the owner for an invitation, then sign in again.',
            onSignOut: () async {
              await signOutAndClear();
              ref.invalidate(profileProvider);
            },
          );
        }
        if (profile.tenantId.isEmpty) {
          return _BlockedScreen(
            title: 'No organisation',
            message:
                'This profile is not linked to an organisation. Ask the owner to re-invite you.',
            onSignOut: () async {
              await signOutAndClear();
              ref.invalidate(profileProvider);
            },
          );
        }
        if (profile.role == 'viewer') {
          return _ReadOnlyNotice(profile: profile, child: child);
        }
        if (!profile.isWriter) {
          return _BlockedScreen(
            title: 'Unknown role',
            message: 'This account has an unsupported role (${profile.role}).',
            onSignOut: () async {
              await signOutAndClear();
              ref.invalidate(profileProvider);
            },
          );
        }
        return child;
      },
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  final String title;
  final String message;
  final String? details;
  final VoidCallback? onRetry;
  final Future<void> Function()? onSignOut;

  const _BlockedScreen({
    required this.title,
    required this.message,
    this.details,
    this.onRetry,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card.outlined(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 40, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  if (details != null) ...[
                    const SizedBox(height: 8),
                    Text(details!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (onRetry != null)
                        OutlinedButton(
                            onPressed: onRetry, child: const Text('Retry')),
                      if (onSignOut != null)
                        FilledButton(
                            onPressed: onSignOut, child: const Text('Sign out')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
                    'View-only mode - signed in as ${profile.displayName} (${profile.role}). Write actions are disabled.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await signOutAndClear();
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
