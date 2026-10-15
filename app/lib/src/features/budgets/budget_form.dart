import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/budget/budget_calculator.dart';
import '../categories/categories_provider.dart';
import 'budgets_provider.dart';

class BudgetFormDialog extends ConsumerStatefulWidget {
  const BudgetFormDialog({super.key});
  @override
  ConsumerState<BudgetFormDialog> createState() => _BudgetFormDialogState();
}

class _BudgetFormDialogState extends ConsumerState<BudgetFormDialog> {
  String? categoryId;
  final limit = TextEditingController();
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool busy = false;
  String? error;

  Future<void> save() async {
    final l = double.tryParse(limit.text.trim());
    if (categoryId == null) {
      setState(() => error = 'Select expense category');
      return;
    }
    if (l == null || l < 0) {
      setState(() => error = 'Valid limit required');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Supabase.instance.client.from('budgets').upsert({
        'category_id': categoryId,
        'fy_year': BudgetCalculator.fyStartYear(month),
        'fy_month': BudgetCalculator.fyMonth(month),
        'limit_amount': l,
      }, onConflict: 'tenant_id,category_id,fy_year,fy_month');
      ref.invalidate(budgetsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    return AlertDialog(
      title: const Text('Set Budget'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            categories.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Categories error: $e'),
              data: (list) {
                final exp =
                    list.where((c) => c.kind == 'expense').toList();
                return DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  hint: const Text('Expense category *'),
                  items: exp
                      .map((c) => DropdownMenuItem(
                          value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => categoryId = v),
                );
              },
            ),
            TextField(
                controller: limit,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Monthly limit Rs *')),
            Row(children: [
              Text(
                  'Month: ${month.year}/${month.month} (${BudgetCalculator.fyLabel(month)})'),
              TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        initialDate: month,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (d != null) {
                      setState(() => month = DateTime(d.year, d.month, 1));
                    }
                  },
                  child: const Text('Pick')),
            ]),
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
