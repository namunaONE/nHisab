import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/budget/budget_calculator.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import '../accounts/accounts_provider.dart';
import '../budgets/budgets_provider.dart';
import '../categories/categories_provider.dart';
import '../loans/loans_provider.dart';
import '../transactions/transactions_provider.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final txnsAsync = ref.watch(transactionsProvider);
    final budgetsAsync = ref.watch(budgetsProvider);
    final loansAsync = ref.watch(loansProvider);
    final fmt = NumberFormat('#,##0.00');
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('nHisab Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---- Net worth card (premium) ----
          accountsAsync.when(
            loading: () => const SkeletonCard(height: 150),
            error: (e, _) => Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(accountsProvider),
                ),
              ),
            ),
            data: (accs) {
              final total = BudgetCalculator.round2(
                  accs.fold(0.0, (s, a) => s + a.computedBalance));
              return Card.outlined(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Net cash in wallets',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              BudgetCalculator.fyLabel(DateTime.now()),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fmt.format(total),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: total >= 0 ? scheme.primary : scheme.error,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        accs.isEmpty
                            ? 'Apply migration 20261015140000 to enable.'
                            : '${accs.length} wallets',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // ---- Cashflow: last 6 AD months ----
          txnsAsync.when(
            loading: () => const SkeletonCard(height: 260),
            error: (e, _) => Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(transactionsProvider),
                ),
              ),
            ),
            data: (txns) {
              final now = DateTime.now();
              final months = List.generate(
                  6,
                  (k) => DateTime(now.year, now.month - 5 + k, 1));
              final incomeByM = List.filled(6, 0.0);
              final expenseByM = List.filled(6, 0.0);
              for (final t in txns) {
                final mi = (t.date.year - months.first.year) * 12 +
                    (t.date.month - months.first.month);
                if (mi < 0 || mi > 5) continue;
                if (t.kind == 'income') {
                  incomeByM[mi] += t.amount;
                } else if (t.kind == 'expense') {
                  expenseByM[mi] += t.amount;
                }
              }
              var peak = 1.0;
              for (var i = 0; i < 6; i++) {
                final m = incomeByM[i] > expenseByM[i]
                    ? incomeByM[i]
                    : expenseByM[i];
                if (m > peak) peak = m;
              }
              const monthNames = [
                'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
              ];
              final totalIn =
                  incomeByM.fold(0.0, (s, v) => s + v);
              final totalOut =
                  expenseByM.fold(0.0, (s, v) => s + v);
              if (txns.isEmpty) {
                return Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: EmptyState(
                      icon: Icons.show_chart,
                      title: 'No transactions yet',
                      subtitle:
                          'Record income/expenses to see cashflow.',
                      ctaLabel: 'Add transaction',
                      onCta: () {
                        ref.invalidate(accountsProvider);
                        ref.invalidate(categoriesProvider);
                      },
                    ),
                  ),
                );
              }
              return Card.outlined(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Cashflow — last 6 months',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              BudgetCalculator.fyLabel(DateTime.now()),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: BarChart(
                          BarChartData(
                            maxY: peak * 1.2 + 1,
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 24,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i > 5) {
                                      return const Text('');
                                    }
                                    return Text(
                                      monthNames[months[i].month - 1],
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  interval: peak / 4,
                                  getTitlesWidget: (value, _) {
                                    if (value == 0) return const Text('');
                                    return Text(
                                      fmt.format(value).replaceAll(',', ''),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            groupsSpace: 10,
                            barGroups: List.generate(6, (i) {
                              return BarChartGroupData(
                                x: i,
                                barsSpace: 4,
                                barRods: [
                                  BarChartRodData(
                                    toY: incomeByM[i],
                                    color: scheme.secondary,
                                    width: 14,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  BarChartRodData(
                                    toY: expenseByM[i],
                                    color: scheme.error,
                                    width: 14,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: scheme.secondary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'In ${fmt.format(totalIn)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: scheme.error,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Out ${fmt.format(totalOut)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // ---- Budget donut (premium with center total) ----
          budgetsAsync.when(
            loading: () => const SkeletonCard(height: 260),
            error: (e, _) => Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(budgetsProvider),
                ),
              ),
            ),
            data: (budgets) {
              if (budgets.isEmpty) {
                return Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: EmptyState(
                      icon: Icons.savings,
                      title: 'No budgets yet',
                      subtitle: 'Set monthly limits to track spending.',
                    ),
                  ),
                );
              }
              final totalLimit = budgets.fold(
                  0.0, (s, b) => s + b.limit);
              final totalSpent = budgets.fold(
                  0.0, (s, b) => s + b.spent);
              final sections = <PieChartSectionData>[];
              final palette = [
                scheme.primary,
                scheme.secondary,
                scheme.tertiary,
                scheme.error,
              ];
              for (var i = 0; i < budgets.length && i < 6; i++) {
                final b = budgets[i];
                final over = BudgetCalculator.isOverspent(
                    limit: b.limit, spent: b.spent);
                sections.add(PieChartSectionData(
                  value: b.limit <= 0 ? 1 : b.limit,
                  color: over ? scheme.error : palette[i % palette.length],
                  radius: 56,
                  titleStyle: const TextStyle(fontSize: 9),
                  borderSide: const BorderSide(
                    color: Colors.white,
                    width: 2,
                  ),
                ));
              }
              return Card.outlined(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Budget split',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              BudgetCalculator.fyLabel(DateTime.now()),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: Row(
                          children: [
                            // Donut chart
                            Expanded(
                              flex: 2,
                              child: PieChart(
                                PieChartData(
                                  sections: sections,
                                  centerSpaceRadius: 34,
                                  sectionsSpace: 4,
                                  startDegreeOffset: -90,
                                ),
                              ),
                            ),
                            // Legend
                            Expanded(
                              flex: 3,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  budgets.length > 6 ? 6 : budgets.length,
                                  (i) {
                                    final b = budgets[i];
                                    final over = BudgetCalculator.isOverspent(
                                        limit: b.limit, spent: b.spent);
                                    final pct =
                                        b.limit <= 0
                                            ? 0.0
                                            : (b.spent / b.limit).clamp(
                                                0.0, 1.0);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: over
                                                  ? scheme.error
                                                  : palette[i % palette.length],
                                              borderRadius: BorderRadius.circular(
                                                  2),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  b.categoryName,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '${fmt.format(b.spent)} / ${fmt.format(b.limit)}',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: over
                                                        ? scheme.error
                                                        : scheme
                                                            .onSurfaceVariant,
                                                    fontWeight: over
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            width: 36,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color:
                                                  scheme.outlineVariant
                                                      .withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(
                                                  3),
                                            ),
                                            child: FractionallySizedBox(
                                              widthFactor: pct,
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: over
                                                      ? scheme.error
                                                      : palette[
                                                          i % palette.length],
                                                  borderRadius: BorderRadius.circular(
                                                      3),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Spent ${fmt.format(totalSpent)} / ${fmt.format(totalLimit)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // ---- Overdue / loan strip ----
          loansAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(loansProvider),
                ),
              ),
            ),
            data: (loans) => Card.outlined(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 32,
                      decoration: BoxDecoration(
                        color: loans.isNotEmpty ? scheme.error : scheme.secondary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${loans.length} active loans',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'open Ledger for dues.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
