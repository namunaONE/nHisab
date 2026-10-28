import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/profiles_provider.dart';
import 'members_provider.dart';

class MembersPage extends ConsumerStatefulWidget {
  const MembersPage({super.key});
  @override
  ConsumerState<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends ConsumerState<MembersPage> {
  final emailCtrl = TextEditingController();
  String inviteRole = 'viewer';
  bool busy = false;
  String? error;

  @override
  void dispose() {
    emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final email = emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => error = 'Valid email required');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await Supabase.instance.client.rpc('create_tenant_invite', params: {
        'p_email': email,
        'p_role': inviteRole,
      });
      emailCtrl.clear();
      ref.invalidate(membersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation created.')));
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    await Supabase.instance.client
        .from('tenant_members')
        .update({'role': newRole})
        .eq('user_id', userId);
    ref.invalidate(membersProvider);
  }

  Future<void> _toggleStatus(String userId, String current) async {
    final next = current == 'active' ? 'suspended' : 'active';
    await Supabase.instance.client
        .from('tenant_members')
        .update({'status': next})
        .eq('user_id', userId);
    ref.invalidate(membersProvider);
  }

  Future<void> _remove(String userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove member?'),
        content: const Text('This removes their access to this organisation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client
        .from('tenant_members')
        .delete()
        .eq('user_id', userId);
    ref.invalidate(membersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(profileProvider).asData?.value?.role == 'owner';
    final members = ref.watch(membersProvider);
    final tenants = ref.watch(myTenantsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Members & Organisations')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Tenant switcher
          tenants.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (list) {
              if (list.length <= 1) return const SizedBox.shrink();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Active organisation',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...list.map((t) => ListTile(
                            title: Text(t['name'] as String),
                            subtitle: Text(t['role'] as String),
                            trailing: t['tenant_id'] ==
                                    Supabase.instance.client.auth.currentUser?.id
                                ? null
                                : null,
                            onTap: () async {
                              await Supabase.instance.client.rpc(
                                  'set_active_tenant',
                                  params: {'p_tenant_id': t['tenant_id']});
                              ref.invalidate(profileProvider);
                              ref.invalidate(membersProvider);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Switched to ${t['name']}')));
                            },
                          )),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          if (isOwner) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Invite member',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: inviteRole,
                      items: const [
                        DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                        DropdownMenuItem(value: 'manager', child: Text('Manager')),
                        DropdownMenuItem(value: 'owner', child: Text('Owner')),
                      ],
                      onChanged: (v) => setState(() => inviteRole = v!),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: busy ? null : _invite,
                      child: Text(busy ? 'Inviting...' : 'Create invite'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text('Members', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (list) => Column(
              children: list.map((m) {
                final isSelf = m.userId ==
                    Supabase.instance.client.auth.currentUser?.id;
                return Card(
                  child: ListTile(
                    title: Text(m.displayName?.isNotEmpty == true
                        ? m.displayName!
                        : (m.email ?? m.userId)),
                    subtitle: Text('${m.email ?? ''} • ${m.status}'),
                    trailing: isOwner && !isSelf
                        ? PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'remove') {
                                _remove(m.userId);
                              } else if (v == 'toggle') {
                                _toggleStatus(m.userId, m.status);
                              } else {
                                _changeRole(m.userId, v);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'manager', child: Text('Make manager')),
                              const PopupMenuItem(value: 'viewer', child: Text('Make viewer')),
                              const PopupMenuItem(value: 'owner', child: Text('Make owner')),
                              PopupMenuItem(value: 'toggle', child: Text(m.status == 'active' ? 'Suspend' : 'Reactivate')),
                              const PopupMenuItem(value: 'remove', child: Text('Remove')),
                            ],
                          )
                        : Text(m.role),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}