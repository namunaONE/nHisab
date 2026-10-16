import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool isSignup = false;
  bool busy = false;
  String? error;

  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (isSignup) {
        await auth.signUp(email: email.text.trim(), password: password.text);
      } else {
        await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('nHisab', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Loan records for Nepal. Sign in to continue.'),
                  const SizedBox(height: 16),
                  TextField(controller: email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 8),
                  TextField(controller: password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true, onSubmitted: (_) => submit()),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.secondary,
                      foregroundColor: scheme.onSecondary,
                    ),
                    child: Text(busy ? 'Please wait...' : (isSignup ? 'Create account' : 'Sign in')),
                  ),
                  TextButton(
                    onPressed: () => setState(() => isSignup = !isSignup),
                    child: Text(isSignup ? 'Have an account? Sign in' : 'New here? Create account'),
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
