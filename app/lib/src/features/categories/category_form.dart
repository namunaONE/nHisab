import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'categories_provider.dart';

class CategoryFormDialog extends ConsumerStatefulWidget {
  const CategoryFormDialog({super.key});
  @override
  ConsumerState<CategoryFormDialog> createState() =>
      _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<CategoryFormDialog> {
  final name = TextEditingController();
  String kind = 'expense';
  bool busy = false;
  String? error;
  String? nameError;

  @override
  void initState() {
    super.initState();
    name.addListener(_validateName);
  }

  @override
  void dispose() {
    name.removeListener(_validateName);
    name.dispose();
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

  Future<void> save() async {
    _validateName();
    if (nameError != null) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client
          .from('categories')
          .insert({'kind': kind, 'name': name.text.trim()});
      ref.invalidate(categoriesProvider);
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
      title: const Text('Add Category'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Kind *'),
              items: const [
                DropdownMenuItem(value: 'income', child: Text('Income')),
                DropdownMenuItem(value: 'expense', child: Text('Expense')),
              ],
              onChanged: (v) => setState(() => kind = v!),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: 'Name *',
                  errorText: nameError,
                )),
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
