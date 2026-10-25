import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_service.dart';
import '../auth/profiles_provider.dart';
import 'parties_provider.dart';
import 'party_form.dart';
import 'party_statement_page.dart';

class PartiesPage extends ConsumerWidget {
  const PartiesPage({super.key});

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
    await AuditLog.write(
        table: 'parties', rowId: id, action: 'archive');
    ref.invalidate(partiesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partiesProvider);
    final canWrite = ref.watch(canWriteProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Parties')),
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
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(
            leading: CircleAvatar(
                child: Text(
                    list[i].name.isNotEmpty ? list[i].name[0] : '?')),
            title: Text(list[i].name),
            subtitle: Text([
              list[i].phone,
              list[i].address
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
                            PartyStatementPage(partyId: list[i].id)),
                  ),
                ),
                if (canWrite) ...[
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Edit party',
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const PartyFormDialog()),
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    tooltip: 'Archive (soft delete)',
                    onPressed: () => _archive(
                        context, ref, list[i].id, list[i].name),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
