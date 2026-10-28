import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecurityPage extends ConsumerStatefulWidget {
  const SecurityPage({super.key});
  @override
  ConsumerState<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends ConsumerState<SecurityPage> {
  List<Factor> factors = const [];
  bool busy = false;
  String? error;
  String? enrollUri;
  String? factorId;
  final codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await Supabase.instance.client.auth.mfa.listFactors();
      setState(() => factors = res.totp);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _enroll() async {
    setState(() { busy = true; error = null; });
    try {
      final res = await Supabase.instance.client.auth.mfa.enroll(
        factorType: FactorType.totp,
        friendlyName: 'nHisab TOTP',
      );
      setState(() {
        factorId = res.id;
        enrollUri = res.totp?.uri;
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verify() async {
    if (factorId == null || codeCtrl.text.trim().isEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      final challenge = await Supabase.instance.client.auth.mfa.challenge(
        factorId: factorId!,
      );
      await Supabase.instance.client.auth.mfa.verify(
        factorId: factorId!,
        challengeId: challenge.id,
        code: codeCtrl.text.trim(),
      );
      setState(() { enrollUri = null; factorId = null; codeCtrl.clear(); });
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MFA enabled.')));
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _unenroll(String id) async {
    setState(() => busy = true);
    try {
      await Supabase.instance.client.auth.mfa.unenroll(id);
      await _refresh();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signOutOthers() async {
    setState(() => busy = true);
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.others);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Other sessions revoked.')));
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Multi-factor authentication (TOTP)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (factors.isEmpty && enrollUri == null)
            FilledButton(
              onPressed: busy ? null : _enroll,
              child: Text(busy ? 'Enrolling...' : 'Enable TOTP MFA'),
            ),
          if (enrollUri != null) ...[
            Text('Scan this URI in your authenticator app:'),
            SelectableText(enrollUri!),
            const SizedBox(height: 8),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Verification code'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy ? null : _verify,
              child: Text(busy ? 'Verifying...' : 'Verify & enable'),
            ),
          ],
          for (final f in factors)
            ListTile(
              title: Text(f.friendlyName ?? f.id),
              subtitle: Text(f.status.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : () => _unenroll(f.id),
              ),
            ),
          const Divider(),
          const Text('Sessions', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: busy ? null : _signOutOthers,
            child: const Text('Sign out all other sessions'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}