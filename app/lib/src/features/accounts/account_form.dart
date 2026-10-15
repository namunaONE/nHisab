import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'accounts_provider.dart';
import 'account_model.dart';

class AccountFormDialog extends ConsumerStatefulWidget {
  final AccountRow? existing;
  const AccountFormDialog({super.key, this.existing});
  @override
  ConsumerState<AccountFormDialog> createState() =>
      _AccountFormDialogState();
}

class _AccountFormDialogState extends ConsumerState<AccountFormDialog> {
  late final TextEditingController name;
  late final TextEditingController opening;
  late String type;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.existing?.name ?? '');
    opening = TextEditingController(
        text: widget.existing != null
            ? widget.existing!.openingBalance.toStringAsFixed(0)
            : '0');
    type = widget.existing?.type ?? 'cash';
  }

  Future<void> save() async {
    final n = name.text.trim();
    final o = double.tryParse(opening.text.trim());
    if (n.isEmpty) {
      setState(() => error = 'Name required');
      return;
    }
    if (o == null || o < 0) {
      setState(() => error = 'Valid opening balance required');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final client = Supabase.instance.client;
      if (widget.existing == null) {
        await client.from('accounts').insert(
            {'name': n, 'type': type, 'opening_balance': o});
      } else {
        // Opening editable only when no txns exist (enforced in UI text;
        // DB allows it — v1 rule documented in docs/04).
        await client.from('accounts').update(
            {'name': n, 'type': type, 'opening_balance': o}).eq(
            'id', widget.existing!.id);
      }
      ref.invalidate(accountsProvider);
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
      title: Text(widget.existing == null ? 'Add Wallet' : 'Edit Wallet'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Name * e.g. Cash, Machhapuchhre Bank')),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type *'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(
                    value: 'mobile_wallet', child: Text('Mobile wallet')),
              ],
              onChanged: (v) => setState(() => type = v!),
            ),
            TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Opening balance Rs *')),
            if (widget.existing != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Changing opening affects all history. Prefer a correction txn.'),
              ),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving...' : 'Save')),
      ],
    );
  }
}
