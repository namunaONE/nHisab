import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/features/auth/auth_gate.dart';
import 'package:nhisab/src/features/auth/profiles_provider.dart';
import 'package:nhisab/src/features/auth/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _initSupabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  try {
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-anon-key',
    );
  } catch (_) {
    // Already initialized across test files in the same run.
  }
}

void main() {
  setUpAll(_initSupabase);

  testWidgets('Signed-out user sees LoginPage', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthState(AuthChangeEvent.signedOut, null),
            ),
          ),
          sessionProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: AuthGate(child: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('Signed-in user with profile sees child', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthState(AuthChangeEvent.signedIn, null),
            ),
          ),
          // Non-null session stands in for an authenticated user; the
          // profile gate is overridden below so no Supabase call happens.
          sessionProvider.overrideWithValue(_fakeSession()),
          profileProvider.overrideWith(
            (ref) async => Profile(
              id: 'u1',
              displayName: 'Tester',
              role: 'owner',
              tenantId: 't1',
              createdAt: DateTime(2026, 1, 1),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AuthGate(child: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Viewer role sees read-only notice', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthState(AuthChangeEvent.signedIn, null),
            ),
          ),
          sessionProvider.overrideWithValue(_fakeSession()),
          profileProvider.overrideWith(
            (ref) async => Profile(
              id: 'u2',
              displayName: 'Viewer',
              role: 'viewer',
              tenantId: 't1',
              createdAt: DateTime(2026, 1, 1),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AuthGate(child: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('View-only mode'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  });
}

/// Minimal stand-in session. Only non-nullness is read by AuthGate.
Session _fakeSession() => Session(
      accessToken: 'fake',
      tokenType: 'bearer',
      user: User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
