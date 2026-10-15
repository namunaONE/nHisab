import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'session_provider.dart';
import 'login_page.dart';

class AuthGate extends ConsumerWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Auth error: $e'))),
      data: (state) {
        final session = state.session ?? ref.watch(sessionProvider);
        if (session == null) return const LoginPage();
        return child;
      },
    );
  }
}
