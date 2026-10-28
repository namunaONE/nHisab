import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../auth/profiles_provider.dart';
import 'parties_provider.dart';
import 'party_form.dart';
import 'party_statement_page.dart';

class PartiesPage extends ConsumerStatefulWidget {
  const PartiesPage({super.key});
  @override
  ConsumerState<PartiesPage> createState() => _PartiesPageState();
}

class _PartiesPageState extends ConsumerState<PartiesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _archive(
      BuildContext context, WidgetRef ref, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive party?'),
        content: Text('Archive $name? Loans stay but party hides.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client.from('parties').update(
        {'deleted_at': DateTime.now().toIso8601String()}).eq('id', id);
    await AuditLog.write(table: 'parties', rowId: id, action: 'archive');
    ref.invalidate(partiesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(partiesProvider);
    final canWrite = ref.watch(canWriteProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parties'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search by name, phone, address...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton(
              onPressed: () => showDialog(
                  context: context, builder: (_) => const PartyFormDialog()),
              child: const Icon(Icons.add),
            )
          : null,
      body: parties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final filtered = _query.isEmpty
              ? list
              : list.where((p) {
                  final q = _query;
                  return p.name.toLowerCase().contains(q) ||
                      (p.phone ?? '').toLowerCase().contains(q) ||
                      (p.address ?? '').toLowerCase().contains(q) ||
                      (p.idNumber ?? '').toLowerCase().contains(q);
                }).toList();
          if (filtered.isEmpty) {
            return const Center(child: Text('No matching parties.'));
          }
          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(
                  child: Text(filtered[i].name.isNotEmpty
                      ? filtered[i].name[0]
                      : '?')),
              title: Text(filtered[i].name),
              subtitle: Text([
                filtered[i].phone,
                filtered[i].address
              ].where((e) => e != null && e.isNotEmpty).join(' | ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.receipt_long, size: 18),
                    tooltip: 'View statement',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              PartyStatementPage(partyId: filtered[i].id)),
                    ),
                  ),
                  if (canWrite) ...[
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      tooltip: 'Edit party',
                      onPressed: () => showDialog(
                          context: context,
                          builder: (_) => PartyFormDialog(party: filtered[i])),
                    ),
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      tooltip: 'Archive (soft delete)',
                      onPressed: () => _archive(
                          context, ref, filtered[i].id, filtered[i].name),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}