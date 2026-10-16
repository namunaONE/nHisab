import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/budget/budget_calculator.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import 'budget_form.dart';
import 'budgets_provider.dart';

class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetsProvider);
    final fmt = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addBudget',
        tooltip: 'Set budget',
        onPressed: () => showDialog(
            context: context, builder: (_) => const BudgetFormDialog()),
        child: const Icon(Icons.add),
      ),
      body: budgetsAsync.when(
        loading: () => const SkeletonList(itemCount: 4),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(budgetsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.savings,
              title: 'No budgets yet',
              subtitle:
                  'Apply migration 20261015140000_budget_tracker_v1, then set monthly limits.\nNepal FY ${BudgetCalculator.fyLabel(DateTime.now())}, no rollover in v1.',
              ctaLabel: 'Set budget',
              onCta: () => showDialog(
                  context: context,
                  builder: (_) => const BudgetFormDialog()),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final b = list[i];
              final remaining = BudgetCalculator.budgetRemaining(
                  limit: b.limit, spent: b.spent);
              final over = BudgetCalculator.isOverspent(
                  limit: b.limit, spent: b.spent);
              final pct =
                  b.limit <= 0 ? 0.0 : (b.spent / b.limit).clamp(0.0, 1.0);
              return Card.outlined(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(b.categoryName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: pct),
                      Text(
                        'Spent ${fmt.format(b.spent)} / ${fmt.format(b.limit)} • Left ${fmt.format(remaining)}',
                        style: TextStyle(
                            color: over
                                ? scheme.error
                                : scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
