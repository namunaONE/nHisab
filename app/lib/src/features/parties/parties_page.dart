import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'parties_provider.dart';
import 'party_form.dart';

class PartiesPage extends ConsumerWidget {
  const PartiesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Parties')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog(context: context, builder: (_) => const PartyFormDialog()),
        child: const Icon(Icons.add),
      ),
      body: parties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(
            leading: CircleAvatar(child: Text(list[i].name.isNotEmpty ? list[i].name[0] : '?')),
            title: Text(list[i].name),
            subtitle: Text([list[i].phone, list[i].address].where((e) => e != null && e.isNotEmpty).join(' | ')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Archive (soft delete)',
              onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                  title: const Text('Archive party?'),
                  content: Text('Archive ${list[i].name}? Loans stay but party hides.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archive'))],
                ));
                if (ok == true) {
                  await Supabase.instance.client.from('parties').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', list[i].id);
                  ref.invalidate(partiesProvider);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
