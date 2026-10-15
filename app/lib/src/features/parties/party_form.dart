import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'parties_provider.dart';

class PartyFormDialog extends ConsumerStatefulWidget {
  const PartyFormDialog({super.key});
  @override
  ConsumerState<PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends ConsumerState<PartyFormDialog> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final idNo = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Name required');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await Supabase.instance.client.from('parties').insert({
        'name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'id_number': idNo.text.trim().isEmpty ? null : idNo.text.trim(),
      });
      ref.invalidate(partiesProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Party'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Party Name * e.g. Madhu (Japan)')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
            TextField(controller: idNo, decoration: const InputDecoration(labelText: 'Citizenship / ID No')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Saving...' : 'Save')),
      ],
    );
  }
}
