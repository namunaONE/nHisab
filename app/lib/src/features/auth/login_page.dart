import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Invite-only sign-in.
///
/// Public sign-up was removed deliberately: a new auth user used to receive
/// an owner profile in the shared tenant, exposing every party, loan, and
/// payment. New users must be invited by an owner (see migration
/// 20261025120000_tenant_membership_rls.sql).
///
/// First run only: while no organisation exists, a setup panel is offered to
/// create the first owner (email prefilled below — skip the SQL/dashboard
/// bootstrap step). The backing RPC refuses once any membership exists.
const String firstOwnerEmail = 'work.htpl@gmail.com';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController(text: firstOwnerEmail);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  // First-owner setup panel state.
  bool? _showSetup; // null = checking, true = show, false = user skipped.
  bool _setupBusy = false;
  String? _setupError;

  // Per-field inline validation state
  String? _emailError;
  String? _passwordError;

  bool _emailValid(String v) {
    final re = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
    return re.hasMatch(v.trim());
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
    if (_password.text.isEmpty) {
      setState(() => _passwordError = 'Password is required');
    } else {
      setState(() => _passwordError = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _checkBootstrap();
  }

  Future<void> _checkBootstrap() async {
    try {
      final needs = await Supabase.instance.client
          .rpc('system_needs_bootstrap') as bool?;
      if (mounted) setState(() => _showSetup = needs == true);
    } catch (_) {
      // Fail closed: if the probe fails, hide the panel (normal login works).
      if (mounted) setState(() => _showSetup = false);
    }
  }

  Future<void> _createFirstOwner() async {
    final email = _email.text.trim();
    if (!_emailValid(email)) {
      setState(() => _setupError = 'Enter a valid email like name@example.com');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _setupError = 'Password must be at least 8 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _setupError = 'Passwords do not match');
      return;
    }
    setState(() {
      _setupBusy = true;
      _setupError = null;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('bootstrap_first_owner', params: {
        'p_email': email,
        'p_password': _password.text,
        'p_tenant_name': 'My Organisation',
      });
      // Owner created: sign straight in; the auth stream takes over.
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: _password.text);
    } on PostgrestException catch (e) {
      setState(() => _setupError = e.message);
    } on AuthException catch (e) {
      setState(() => _setupError = e.message);
    } catch (e) {
      setState(() => _setupError = e.toString());
    } finally {
      if (mounted) setState(() => _setupBusy = false);
    }
  }

  Future<void> _submit() async {
    _validateEmail();
    _validatePassword();
    if (_emailError != null || _passwordError != null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    _validateEmail();
    if (_emailError != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: Uri.base.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'If that email is registered, a password reset link has been sent.'),
      ));
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
    _confirm.dispose();
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
                    'Sign in',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Loan records for Nepal. Sign in to continue.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'nHisab is invite-only. Ask your organisation owner for an invitation.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: 'Email *',
                      hintText: 'name@example.com',
                      errorText: _emailError,
                    ),
                    onChanged: (_) => _validateEmail(),
                  ),
                  if (_showSetup == null) ...[
                    const SizedBox(height: 12),
                    const Center(child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                  ] else if (_showSetup == true)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('First-time setup',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 4),
                          Text(
                            'No organisation exists yet. Creating the first '
                            'owner here (email above) skips the manual '
                            'SQL/dashboard bootstrap step. This option '
                            'disappears once the owner exists.',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: 'New password * (min 8 chars)',
                              hintText: 'Choose a strong password',
                              errorText: _passwordError,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _confirm,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              labelText: 'Confirm password *',
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_setupError != null)
                            Text(_setupError!,
                                style: TextStyle(color: scheme.error)),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed:
                                _setupBusy ? null : _createFirstOwner,
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.secondary,
                              foregroundColor: scheme.onSecondary,
                            ),
                            child: Text(_setupBusy
                                ? 'Creating...'
                                : 'Create first owner & sign in'),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _setupBusy
                                ? null
                                : () => setState(() {
                                      _showSetup = false;
                                      _setupError = null;
                                    }),
                            child: const Text('Skip'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    TextField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password *',
                        hintText: 'Your password',
                        errorText: _passwordError,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      onChanged: (_) => _validatePassword(),
                    ),
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
                      child: Text(_busy ? 'Please wait...' : 'Sign in'),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _busy ? null : _resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
