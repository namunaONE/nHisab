import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key});
  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  bool inApp = true;
  bool email = true;
  bool sms = false;
  int dueSoonDays = 7;
  bool busy = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final tid = await client.rpc('current_tenant_id');
      final uid = client.auth.currentUser?.id;
      if (tid == null || uid == null) return;
      final row = await client
          .from('notification_preferences')
          .select('*')
          .eq('tenant_id', tid)
          .eq('user_id', uid)
          .maybeSingle();
      if (row != null) {
        setState(() {
          inApp = (row['in_app'] as bool?) ?? true;
          email = (row['email'] as bool?) ?? true;
          sms = (row['sms'] as bool?) ?? false;
          dueSoonDays = (row['due_soon_days'] as num?)?.toInt() ?? 7;
          loaded = true;
        });
      } else {
        setState(() => loaded = true);
      }
    } catch (_) {
      setState(() => loaded = true);
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final client = Supabase.instance.client;
      final tid = await client.rpc('current_tenant_id');
      final uid = client.auth.currentUser?.id;
      if (tid == null || uid == null) return;
      await client.from('notification_preferences').upsert({
        'tenant_id': tid,
        'user_id': uid,
        'in_app': inApp,
        'email': email,
        'sms': sms,
        'due_soon_days': dueSoonDays,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preferences saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('In-app notifications'),
            value: inApp,
            onChanged: (v) => setState(() => inApp = v),
          ),
          SwitchListTile(
            title: const Text('Email alerts'),
            value: email,
            onChanged: (v) => setState(() => email = v),
          ),
          SwitchListTile(
            title: const Text('SMS alerts'),
            value: sms,
            onChanged: (v) => setState(() => sms = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Due-soon window (days):'),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: TextEditingController(text: dueSoonDays.toString()),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => dueSoonDays = int.tryParse(v) ?? dueSoonDays,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : _save,
            child: Text(busy ? 'Saving...' : 'Save preferences'),
          ),
        ],
      ),
    );
  }
}