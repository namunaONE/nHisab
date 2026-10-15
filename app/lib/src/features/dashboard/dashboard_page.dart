import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/budget/budget_calculator.dart';
import '../accounts/accounts_provider.dart';
import '../budgets/budgets_provider.dart';
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
          // Net worth card
          accountsAsync.when(
            loading: () => const Card.outlined(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Loading wallets…'))),
            error: (e, _) => Card.outlined(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Wallets error: $e'))),
            data: (accs) {
              final total = BudgetCalculator.round2(
                  accs.fold(0.0, (s, a) => s + a.computedBalance));
              return Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Net cash in wallets',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(fmt.format(total),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: scheme.primary)),
                      Text(
                          accs.isEmpty
                              ? 'Apply migration 20261015140000 to enable.'
                              : '${accs.length} wallets • ${BudgetCalculator.fyLabel(DateTime.now())}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // Cashflow: last 6 AD months, income vs expense per month
          txnsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Txns error: $e'),
            data: (txns) {
              final now = DateTime.now();
              final months = List.generate(
                  6,
                  (k) => DateTime(
                      now.year, now.month - 5 + k, 1));
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
              return Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cashflow — last 6 months',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: BarChart(
                          BarChartData(
                            maxY: peak * 1.2 + 1,
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i > 5) {
                                      return const Text('');
                                    }
                                    return Text(
                                        monthNames[
                                            months[i].month - 1],
                                        style: const TextStyle(
                                            fontSize: 10));
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles:
                                      SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            groupsSpace: 6,
                            barGroups: List.generate(6, (i) {
                              return BarChartGroupData(x: i, barRods: [
                                BarChartRodData(
                                    toY: incomeByM[i],
                                    color: scheme.secondary,
                                    width: 7,
                                    borderRadius:
                                        BorderRadius.circular(2)),
                                BarChartRodData(
                                    toY: expenseByM[i],
                                    color: scheme.error,
                                    width: 7,
                                    borderRadius:
                                        BorderRadius.circular(2)),
                              ]);
                            }),
                          ),
                        ),
                      ),
                      Text(
                          'In ${fmt.format(totalIn)} • Out ${fmt.format(totalOut)} (green=in, red=out)',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // Budget donut
          budgetsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Text('Budgets error: $e'),
            data: (budgets) {
              if (budgets.isEmpty) {
                return const Card.outlined(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No budgets yet — set monthly limits.'),
                  ),
                );
              }
              final sections = <PieChartSectionData>[];
              final palette = [
                scheme.primary,
                scheme.secondary,
                scheme.tertiary,
                scheme.error,
              ];
              for (var i = 0; i < budgets.length && i < 6; i++) {
                final b = budgets[i];
                sections.add(PieChartSectionData(
                  value: b.limit <= 0 ? 1 : b.limit,
                  title: b.categoryName,
                  color: palette[i % palette.length],
                  radius: 56,
                  titleStyle: const TextStyle(fontSize: 10),
                ));
              }
              return Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget split',
                          style: Theme.of(context).textTheme.titleMedium),
                      SizedBox(
                        height: 180,
                        child: PieChart(PieChartData(
                            sections: sections,
                            centerSpaceRadius: 28)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // Overdue / loan strip
          loansAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (loans) => Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    '${loans.length} active loans in current filter • open Ledger for dues.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
