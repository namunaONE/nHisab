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
  // Per-field inline validation state
  String? nameError;
  String? openingError;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.existing?.name ?? '');
    opening = TextEditingController(
        text: widget.existing != null
            ? widget.existing!.openingBalance.toStringAsFixed(0)
            : '0');
    type = widget.existing?.type ?? 'cash';
    name.addListener(_validateName);
    opening.addListener(_validateOpening);
  }

  @override
  void dispose() {
    name.removeListener(_validateName);
    opening.removeListener(_validateOpening);
    name.dispose();
    opening.dispose();
    super.dispose();
  }

  void _validateName() {
    final n = name.text.trim();
    if (n.isEmpty) {
      setState(() => nameError = 'Name is required');
    } else if (n.length < 2) {
      setState(() => nameError = 'Name too short (min 2 chars)');
    } else {
      setState(() => nameError = null);
    }
  }

  void _validateOpening() {
    final o = double.tryParse(opening.text.trim());
    if (opening.text.trim().isEmpty) {
      setState(() => openingError = null);
    } else if (o == null) {
      setState(() => openingError = 'Enter a number like 15000.00');
    } else if (o < 0) {
      setState(() => openingError = 'Opening balance cannot be negative');
    } else {
      setState(() => openingError = null);
    }
  }

  Future<void> save() async {
    // Run inline validation first
    _validateName();
    _validateOpening();
    if (nameError != null || openingError != null) return;

    final n = name.text.trim();
    final o = double.tryParse(opening.text.trim());
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
                decoration: InputDecoration(
                  labelText: 'Name * e.g. Cash, Machhapuchhre Bank',
                  errorText: nameError,
                )),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Opening balance Rs *',
                  errorText: openingError,
                )),
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
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Please wait...' : 'Save')),
      ],
    );
  }
}
