import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _phone = TextEditingController();
  bool _isSignup = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  bool _terms = false;

  // Per-field inline validation state
  String? _emailError;
  String? _passwordError;
  String? _displayNameError;
  String? _termsError;

  bool _emailValid(String v) {
    final re = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return re.hasMatch(v.trim());
  }

  bool _passwordStrong(String v) {
    return v.length >= 8 && RegExp(r'[0-9]').hasMatch(v) && RegExp(r'[A-Z]').hasMatch(v);
  }

  void _validateEmail() {
    final v = _email.text.trim();
    if (v.isEmpty) {
      setState(() => _emailError = 'Email is required');
    } else if (!_emailValid(v)) {
      setState(() => _emailError = 'Enter a valid email like name@example.com');
    } else {
      setState(() => _emailError = null);
    }
  }

  void _validatePassword() {
    final v = _password.text;
    if (v.isEmpty) {
      setState(() => _passwordError = null);
    } else if (!_passwordStrong(v)) {
      setState(() => _passwordError = '8+ chars, one number, one uppercase');
    } else {
      setState(() => _passwordError = null);
    }
  }

  void _validateDisplayName() {
    final v = _displayName.text.trim();
    if (!_isSignup) {
      setState(() => _displayNameError = null);
      return;
    }
    if (v.isEmpty) {
      setState(() => _displayNameError = 'Full name is required');
    } else if (v.length < 2) {
      setState(() => _displayNameError = 'Name too short (min 2 chars)');
    } else {
      setState(() => _displayNameError = null);
    }
  }

  void _validateTerms() {
    if (!_isSignup) {
      setState(() => _termsError = null);
      return;
    }
    setState(() => _termsError = _terms ? null : 'You must accept the terms');
  }

  Future<void> _submit() async {
    // Run all inline validation first
    _validateEmail();
    _validatePassword();
    _validateDisplayName();
    _validateTerms();
    if (_emailError != null ||
        _passwordError != null ||
        _displayNameError != null ||
        _termsError != null) {
      return;
    }

    setState(() { _busy = true; _error = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignup) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {
            'display_name': _displayName.text.trim(),
            'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          },
        );
        if (res.user == null) {
          setState(() => _error = 'Signup failed. Check your email and try again.');
          return;
        }
        setState(() => _error = null);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Account created. Check your email to verify.'),
        ));
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isSignup ? 'Create account' : 'Sign in',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isSignup
                        ? 'Join nHisab to manage your loan records for Nepal.'
                        : 'Loan records for Nepal. Sign in to continue.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (_isSignup) ...[
                    TextField(
                      controller: _displayName,
                      keyboardType: TextInputType.name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Full Name *',
                        hintText: 'e.g. Madhav Koirala',
                        errorText: _displayNameError,
                      ),
                      onChanged: (_) => _validateDisplayName(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Email *',
                      hintText: 'name@example.com',
                      errorText: _emailError,
                    ),
                    onChanged: (_) => _validateEmail(),
                  ),
                  const SizedBox(height: 8),
                  if (_isSignup) ...[
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        hintText: '+977 98XXXXXXXX',
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      hintText: _isSignup
                          ? '8+ chars, one number, one uppercase'
                          : 'Your password',
                      errorText: _passwordError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20,
                        ),
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    onChanged: (_) => _validatePassword(),
                  ),
                  const SizedBox(height: 8),
                  if (_isSignup) ...[
                    Row(
                      children: [
                        Checkbox(
                          value: _terms,
                          onChanged: (v) => setState(() => _terms = v ?? false),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodySmall,
                              children: [
                                const TextSpan(text: 'I accept the '),
                                TextSpan(
                                  text: 'Terms of Service',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_termsError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _termsError!,
                        style: TextStyle(
                          color: scheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.secondary,
                      foregroundColor: scheme.onSecondary,
                    ),
                    child: Text(_busy
                        ? 'Please wait...'
                        : (_isSignup ? 'Create account' : 'Sign in')),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignup ? 'Already have an account? ' : 'New here? ',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: () => setState(() => _isSignup = !_isSignup),
                        child: Text(
                          _isSignup ? 'Sign in' : 'Create account',
                        ),
                      ),
                    ],
                  ),
                  if (!_isSignup) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        // Forgot password handled by Supabase reset flow
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Password reset sent to your email.'),
                        ));
                      },
                      child: const Text('Forgot password?'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'We will send a verification email before first sign in.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
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
